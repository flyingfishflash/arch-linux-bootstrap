## Arch-Linux-Bootstrap: A Script to bootstrap an Arch Linux image

Derived from the forked repository as well as [this gist](https://gist.github.com/anthonygclark/444f7c569c7b414c36c7c05714ea4a1e) which was immensely helpful.

The scripts in this package can be used to generate a minimal disk image of Arch Linux, i.e.
as a base for virtual machines. The images are geared towards libvirt/kvm but it shouldn't be 
much of a problem to adapt the scripts for other environments.

### Features

The resulting image is intended to be provisioned by Terraform, and to be paired with a volume image containing cloud-init 'user-data'. 

To provision QEMU/KVM machines with Terraform, you'll need this plugin: [terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)

An example Terraform configuration in provided.

Currently, *hostname* is the only element of the Cloud-Init user-data structure that's supported, but it could be expanded. This is just a proof of concept that the user-data structure could be imported directly to an Ansible playbook and acted upon.

More information on Cloud-Init user-data is found in their [documentation](https://cloudinit.readthedocs.io/en/latest/topics/examples.html).

The image will work when manually provisioned via the *virt-viewer* interface, though the *cloud-intialization* systemd service will fail until it's disabled.

### Usage

Create a file named `secret` in the `ansible` subdirectory. Insert a hash representing the root password.

Execute `bootstrap.sh` as root in Arch Linux.

### Network setup

Networking is managed by NetworkManager.

### SSH Setup

SSH is enabled.

The only user permitted to login is the *provision* user. Provide the public key by creating a file named `provision_public_key.pub` in the `ansible` directory.

### Alternatives

[Image Bootstrap](https://github.com/hartwork/image-bootstrap)


