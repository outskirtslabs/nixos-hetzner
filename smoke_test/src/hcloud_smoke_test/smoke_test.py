import argparse
import logging
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Optional

import paramiko
from hcloud import Client
from hcloud.images import Image
from hcloud.server_types import ServerType
from hcloud.servers import Server
from hcloud.ssh_keys import SSHKey

ARCH_TO_HCLOUD_ARCH = {
    "x86_64-linux": "x86",
    "aarch64-linux": "arm",
}

ARCH_TO_SERVER_TYPE = {
    "x86": "cx22",
    "arm": "cax11",
}


def upload_image(
    image_path: Path,
    architecture: str,
    description: str,
) -> int:
    """Upload image using hcloud-upload-image CLI, returns image ID."""
    arch = ARCH_TO_HCLOUD_ARCH.get(architecture, architecture)

    cmd = [
        "hcloud-upload-image",
        "upload",
        f"--image-path={image_path}",
        f"--architecture={arch}",
        f"--description={description}",
    ]

    logging.info(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.stdout:
        logging.debug(f"stdout: {result.stdout}")
    if result.stderr:
        for line in result.stderr.splitlines():
            logging.info(f"hcloud-upload-image: {line}")

    if result.returncode != 0:
        raise RuntimeError(
            f"hcloud-upload-image failed with code {result.returncode}: {result.stderr}"
        )

    combined_output = result.stderr + result.stdout
    match = re.search(r"image=(\d+)", combined_output)
    if not match:
        raise RuntimeError(
            f"Failed to parse image ID from hcloud-upload-image output: {combined_output}"
        )

    return int(match.group(1))


def create_ssh_key(client: Client, name: str) -> tuple[SSHKey, str]:
    """Create temporary SSH key pair, returns (hcloud_key, private_key_path)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        key_path = Path(tmpdir) / "id_ed25519"
        subprocess.run(
            ["ssh-keygen", "-t", "ed25519", "-N", "", "-f", str(key_path)],
            check=True,
            capture_output=True,
        )

        public_key = key_path.with_suffix(".pub").read_text().strip()
        private_key_content = key_path.read_text()

    hcloud_key = client.ssh_keys.create(name=name, public_key=public_key)
    logging.info(f"Created SSH key: {hcloud_key.data_model.name}")

    private_key_file = tempfile.NamedTemporaryFile(
        mode="w", delete=False, suffix=".key"
    )
    private_key_file.write(private_key_content)
    private_key_file.close()
    os.chmod(private_key_file.name, 0o600)

    return hcloud_key, private_key_file.name


def wait_for_server_running(
    client: Client, server: Server, timeout: int = 300
) -> Server:
    """Wait for server to reach 'running' status."""
    start = time.time()
    while time.time() - start < timeout:
        server = client.servers.get_by_id(server.data_model.id)
        status = server.data_model.status
        if status == Server.STATUS_RUNNING:
            logging.info(f"Server {server.data_model.name} is running")
            return server
        logging.debug(f"Server status: {status}, waiting...")
        time.sleep(5)
    raise TimeoutError(f"Server did not reach 'running' status within {timeout}s")


def wait_for_ssh(
    host: str, private_key_path: str, timeout: int = 300
) -> paramiko.SSHClient:
    """Wait for SSH to become available and return connected client."""
    start = time.time()
    key = paramiko.Ed25519Key.from_private_key_file(private_key_path)

    while time.time() - start < timeout:
        try:
            ssh_client = paramiko.SSHClient()
            ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh_client.connect(host, username="root", pkey=key, timeout=10)
            logging.info(f"SSH connection established to {host}")
            return ssh_client
        except (paramiko.SSHException, OSError) as e:
            logging.debug(f"SSH not ready: {e}")
            time.sleep(5)

    raise TimeoutError(f"SSH not available within {timeout}s")


def verify_system_ready(ssh_client: paramiko.SSHClient) -> bool:
    """Verify system has finished booting via systemd."""
    logging.info("Checking systemd status...")

    # Wait for systemd to finish booting
    # Returns: running, degraded, starting, initializing, etc.
    _, stdout, stderr = ssh_client.exec_command(
        "systemctl is-system-running --wait", timeout=120
    )
    output = stdout.read().decode().strip()
    exit_code = stdout.channel.recv_exit_status()

    logging.info(f"systemctl is-system-running: {output}")

    # "running" = all units active, "degraded" = some failed but system usable
    if output in ("running", "degraded"):
        logging.info("System boot completed successfully")
        return True

    err_output = stderr.read().decode()
    logging.error(f"System not ready (exit {exit_code}): {output} {err_output}")
    return False


def cleanup(
    client: Client,
    server: Optional[Server],
    image_id: Optional[int],
    ssh_key: Optional[SSHKey],
    private_key_path: Optional[str],
    delete_image: bool = True,
) -> None:
    """Clean up all created resources."""
    if server:
        try:
            logging.info(f"Deleting server {server.data_model.name}")
            action = client.servers.delete(server)
            action.wait_until_finished()
        except Exception as e:
            logging.warning(f"Failed to delete server: {e}")

    if image_id and delete_image:
        try:
            logging.info(f"Deleting image {image_id}")
            image = client.images.get_by_id(image_id)
            client.images.delete(image)
        except Exception as e:
            logging.warning(f"Failed to delete image: {e}")

    if ssh_key:
        try:
            logging.info(f"Deleting SSH key {ssh_key.data_model.name}")
            client.ssh_keys.delete(ssh_key)
        except Exception as e:
            logging.warning(f"Failed to delete SSH key: {e}")

    if private_key_path and os.path.exists(private_key_path):
        os.unlink(private_key_path)


def smoke_test(
    image_path: Optional[Path],
    architecture: str,
    run_id: Optional[str] = None,
    image_id: Optional[int] = None,
    skip_cleanup: bool = False,
    keep_image_on_failure: bool = False,
    timeout: int = 600,
) -> None:
    """Main smoke test orchestration."""
    token = os.environ.get("HCLOUD_TOKEN")
    if not token:
        raise RuntimeError("HCLOUD_TOKEN environment variable is required")

    # Increase poll_max_retries to handle longer server creation times
    # Default is 120 with exponential backoff, which can timeout too quickly
    client = Client(token=token, poll_interval=2.0, poll_max_retries=300)

    resource_suffix = run_id or str(int(time.time()))
    server_name = f"smoke-test-{resource_suffix}"
    ssh_key_name = f"smoke-test-key-{resource_suffix}"

    created_image_id: Optional[int] = None
    uploaded_image: bool = False
    server: Optional[Server] = None
    ssh_key: Optional[SSHKey] = None
    private_key_path: Optional[str] = None
    test_failed: bool = True  # Assume failure until proven otherwise

    try:
        # 1. Upload image if needed
        if image_id:
            logging.info(f"Using existing image {image_id}")
            created_image_id = image_id
        else:
            if image_path is None:
                raise RuntimeError("Either --image-path or --image-id is required")
            logging.info(f"Uploading image from {image_path}")
            logging.info(f"(this could take awhile!)")
            created_image_id = upload_image(
                image_path, architecture, f"smoke-test-{resource_suffix}"
            )
            uploaded_image = True
            logging.info(f"Uploaded image: {created_image_id}")

        # 2. Create SSH key
        logging.info("Creating SSH key")
        ssh_key, private_key_path = create_ssh_key(client, ssh_key_name)

        # 3. Create server
        arch = ARCH_TO_HCLOUD_ARCH.get(architecture, architecture)
        server_type = ARCH_TO_SERVER_TYPE[arch]
        logging.info(f"Creating server '{server_name}' with type {server_type}")

        response = client.servers.create(
            name=server_name,
            server_type=ServerType(name=server_type),
            image=Image(id=created_image_id),
            ssh_keys=[ssh_key],
        )
        response.action.wait_until_finished()
        server = response.server
        logging.info(f"Created server: {server.data_model.name}")

        # 4. Wait for server to be running
        logging.info(f"Waiting for server to be running (timeout: {timeout}s)")
        server = wait_for_server_running(client, server, timeout=timeout)

        # 5. Get public IP
        public_ip = server.data_model.public_net.ipv4.ip
        logging.info(f"Server IP: {public_ip}")

        # 6. Wait for SSH and verify
        logging.info("Waiting for SSH connectivity")
        ssh_client = wait_for_ssh(public_ip, private_key_path, timeout=timeout)

        try:
            # 7. Verify system is ready
            if not verify_system_ready(ssh_client):
                raise RuntimeError("System verification failed")
        finally:
            ssh_client.close()

        logging.info("Smoke test passed!")
        test_failed = False

    except Exception as e:
        logging.error(f"Smoke test failed: {e}")
        test_failed = True
        raise
    finally:
        if skip_cleanup:
            logging.info("Skipping cleanup (--skip-cleanup specified)")
            if server:
                logging.info(
                    f"Server: {server.data_model.name} ({server.data_model.public_net.ipv4.ip})"
                )
            if created_image_id:
                logging.info(f"Image ID: {created_image_id}")
        else:
            should_delete_image = uploaded_image
            if test_failed and keep_image_on_failure and uploaded_image:
                should_delete_image = False
                logging.info(
                    f"Keeping image {created_image_id} for debugging (--keep-image-on-failure)"
                )

            cleanup(
                client,
                server,
                created_image_id,
                ssh_key,
                private_key_path,
                delete_image=should_delete_image,
            )


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Smoke test a NixOS image on Hetzner Cloud"
    )
    parser.add_argument(
        "--image-path",
        type=Path,
        help="Path to the disk image (required unless --image-id is provided)",
    )
    parser.add_argument(
        "--architecture",
        required=True,
        choices=["x86_64-linux", "aarch64-linux"],
        help="CPU architecture of the image",
    )
    parser.add_argument(
        "--image-id",
        type=int,
        help="Use existing Hetzner image ID (skip upload)",
    )
    parser.add_argument(
        "--run-id",
        help="Unique identifier for this test run (used in resource names)",
    )
    parser.add_argument(
        "--skip-cleanup",
        action="store_true",
        help="Don't delete resources after the test",
    )
    parser.add_argument(
        "--keep-image-on-failure",
        action="store_true",
        help="Keep the uploaded image if the test fails (useful for debugging)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Timeout in seconds for operations (default: 600)",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )

    if not args.image_path and not args.image_id:
        parser.error("Either --image-path or --image-id is required")

    smoke_test(
        image_path=args.image_path,
        architecture=args.architecture,
        run_id=args.run_id,
        image_id=args.image_id,
        skip_cleanup=args.skip_cleanup,
        keep_image_on_failure=args.keep_image_on_failure,
        timeout=args.timeout,
    )


if __name__ == "__main__":
    main()
