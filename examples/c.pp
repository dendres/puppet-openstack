
#
# openstack C
# - controller server
# - compute server
# - single interfaces on each server
# - flat single vlan
# - openvswitch
# - NO: quantum-l3, quantum-lbaas
#

# https://github.com/stackforge/puppet-openstack
# some test scenarios:
# http://wiki.debian.org/OpenStackPuppetHowto
# XXX later run tempest tests
#
# make br100 usinb bridge-utils ????
# set promiscuous mode on the bridged adapter
# 
# #/etc/network/interfaces
# auto eth1
# iface eth1 inet manual
#   up ifconfig $IFACE 0.0.0.0 up
#   up ifconfig $IFACE promisc
#
# create cinder-volumes LVM volume group
# parted /dev/sdb mkpart prmary 1 100%
# vgcreate cinder-volumes /dev/sdb1
#
# apt-get install puppet rake git
# puppet module install puppetlabs-firewall
#
# cd /etc/puppet/modules/openstack
# rake modules:clone
# puppet apply --modulepath /etc/puppet/modules site.pp --certname openstack_controller
# puppet apply --modulepath /etc/puppet/modules site.pp --certname openstack_compute
#

# assumes that eth0 is the public interface
$public_interface        = 'em1'
$public_address          = $ipaddress_em1

# assumes that eth1 is the interface that will be used for the vm network
# this configuration assumes this interface is active but does not have an
# ip address allocated to it.
$private_interface       = 'br100'

# credentials
$cinder_db_password      = 'cinder_pass'
$cinder_user_password    = 'cinder_pass'
$glance_db_password      = 'glance_pass'
$glance_user_password    = 'glance_pass'
$keystone_db_password    = 'keystone_db_pass'
$keystone_admin_token    = 'keystone_admin_token'
$nova_db_password        = 'nova_pass'
$nova_user_password      = 'nova_pass'
$quantum_db_password     = 'quantum_pass'
$quantum_user_password   = 'quantum_pass'
$rabbit_password         = 'openstack_rabbit_password'
$rabbit_user             = 'openstack_rabbit_user'


$admin_email             = 'root@localhost'
$admin_password          = 'keystone_admin'
$secret_key              = 'dummy_secret_key' # XXX WTF?
$metadata_shared_secret  = 'metadata_shared_secret'
$fixed_network_range     = '10.10.14.0/24'
$floating_network_range  = false
$auto_assign_floating_ip = false

# switch this to true to have all service log at verbose
$verbose                 = true


$controller_node_address  = '10.10.12.14'
$controller_node_public   = $controller_node_address
$controller_node_internal = $controller_node_address
$sql_connection         = "mysql://nova:${nova_db_password}@${controller_node_internal}/nova"


# deploy a script that can be used to test nova
class { 'openstack::test_file': }


node /openstack_controller/ {
  # class { 'nova::volume': enabled => true }
  # class { 'nova::volume::iscsi': }

  class { 'openstack::controller':
    public_address          => $controller_node_public,
    public_interface        => $public_interface,
    private_interface       => $private_interface,
    bridge_interface        => $private_interface,
    internal_address        => $controller_node_internal,
    floating_range          => $floating_network_range,
    fixed_range             => $fixed_network_range,
    # by default it does not enable multi-host mode
    multi_host              => true,
    # by default is assumes flat dhcp networking mode
    network_manager         => 'nova.network.manager.FlatDHCPManager',
    verbose                 => $verbose,
    auto_assign_floating_ip => $auto_assign_floating_ip,
    mysql_root_password     => $mysql_root_password,
    admin_email             => $admin_email,
    admin_password          => $admin_password,
    keystone_db_password    => $keystone_db_password,
    keystone_admin_token    => $keystone_admin_token,
    glance_db_password      => $glance_db_password,
    glance_user_password    => $glance_user_password,
    nova_db_password        => $nova_db_password,
    nova_user_password      => $nova_user_password,
    rabbit_password         => $rabbit_password,
    rabbit_user             => $rabbit_user,
    # export_resources      => false,
    secret_key              => $secret_key,
    quantum_db_password     => $quantum_db_password,
    quantum_user_password   => $quantum_user_password,
    metadata_shared_secret  => $metadata_shared_secret,
    cinder_db_password      => $cinder_db_password,
    cinder_user_password    => $cinder_user_password,
  }

  class { 'openstack::auth_file':
    admin_password       => $admin_password,
    keystone_admin_token => $keystone_admin_token,
    controller_node      => $controller_node_internal,
  }
}

# nothing in compute should need mysql database access!!! 
# that is what nova-conductor is for!!!
node /openstack_compute/ {
  class { 'openstack::compute':
    public_interface   => $public_interface,
    private_interface  => $private_interface,
    internal_address   => $public_address, # ?????????????
    libvirt_type       => 'kvm',
    fixed_range        => $fixed_network_range,
    network_manager    => 'nova.network.manager.FlatDHCPManager',
    multi_host         => true,
    # sql_connection     => $sql_connection,
    nova_db_password   => $nova_db_password,
    nova_user_password => $nova_user_password,
    quantum_user_password   => $quantum_user_password,
    cinder_db_password      => $cinder_db_password,
    rabbit_host        => $controller_node_internal,
    rabbit_password    => $rabbit_password,
    rabbit_user        => $rabbit_user,
    glance_api_servers => "${controller_node_internal}:9292",
    vncproxy_host      => $controller_node_public,
    vnc_enabled        => true,
    verbose            => $verbose,
    manage_volumes     => true,
    volume_group       => 'cinder-volumes'
  }
}

