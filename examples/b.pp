
#
# openstack B
# - controller server
# - compute server
# - single interfaces on each server
# - flat single vlan
# - linux bridge network
# - NO: quantum-l3, quantum-lbaas, ovs, swift
#

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

# in this example we have 2 hosts with identical network configuration
# $ipaddress fact is available and referrs to the only IP configured on each server
$interface               = 'em1'

# the compute node will need to know which host is the controller:
$controller_address      = '10.10.12.15'

$verbose                 = true
$region                  = 'RegionOne'
$mysql_root_password     = 'sql_pass'
$admin_email             = 'root@localhost'  # 'admin' user in keystone
$admin_password          = 'keystone_admin'
$keystone_admin_tenant   = 'admin'
$keystone_db_password    = 'keystone_db_pass'
$keystone_admin_token    = 'keystone_admin_token'
$cinder_db_password      = 'cinder_pass'
$cinder_user_password    = 'cinder_pass'
$glance_db_password      = 'glance_pass'
$glance_user_password    = 'glance_pass'
$glance_api_servers      = "${controller_address}:9292"
$nova_admin_tenant_name  = 'services'
$nova_db_password        = 'nova_pass'
$nova_user_password      = 'nova_pass'
$nova_enabled_apis       = 'ec2,osapi_compute,metadata'
$nova_cluster_id         = 'localcluster'
$quantum_db_password     = 'quantum_pass'
$quantum_user_password   = 'quantum_pass'
$metadata_shared_secret  = 'metadata_shared_secret'
$rabbit_host             = $controller_address
$rabbit_virtual_host     = '/'
$rabbit_user             = 'openstack_rabbit_user'
$rabbit_password         = 'openstack_rabbit_password'
$horizon_secret_key      = 'horizon_secret_key'
$fixed_network_range     = '10.10.14.0/24'
$floating_network_range  = false
$auto_assign_floating_ip = false


class { 'openstack::test_file': }

class { 'openstack::auth_file':
  admin_password       => $admin_password,
  keystone_admin_token => $keystone_admin_token,
  controller_node      => $controller_node_internal,
}

node /openstack_controller/ {
  Class['openstack::db::mysql'] -> Class['openstack::keystone']
  Class['openstack::db::mysql'] -> Class['openstack::nova::controller']
  Class['openstack::db::mysql'] -> Class['openstack::glance']
  Class['glance::db::mysql']    -> Class['glance::registry']

  # resources { 'nova_config':
  #   purge => true,
  # }

  class { 'openstack::db::mysql':
    mysql_bind_address     => '127.0.0.1',
    mysql_account_security => true,
    allowed_hosts          => '%',
    mysql_root_password    => $mysql_root_password,
    keystone_db_password   => $keystone_db_password,
    glance_db_password     => $glance_db_password,
    nova_db_password       => $nova_db_password,
    cinder_db_password     => $cinder_db_password,
    quantum_db_password    => $quantum_db_password,
  }

  class { 'openstack::keystone':
    verbose               => $verbose,
    region                => $region,

    public_address        => $ipaddress,
    internal_address      => $ipaddress,
    admin_address         => $ipaddress,

    db_password           => $keystone_db_password,
    admin_token           => $keystone_admin_token,
    admin_tenant          => $keystone_admin_tenant,
    admin_email           => $admin_email,
    admin_password        => $admin_password,

    cinder_user_password  => $cinder_user_password,
    glance_user_password  => $glance_user_password,
    nova_user_password    => $nova_user_password,
    quantum_user_password => $quantum_user_password,
  }

  class { 'openstack::glance':
    verbose          => $verbose,
    db_password      => $glance_db_password,
    user_password    => $glance_user_password,
    backend          => 'file',
  }

  class { 'openstack::nova::controller':
    verbose                 => $verbose,
    db_host                 => '127.0.0.1',
    public_address          => $ipaddress,
    public_interface        => $interface,
    private_interface       => $interface,

    quantum_user_password   => $quantum_user_password,
    metadata_shared_secret  => $metadata_shared_secret,

    nova_admin_tenant_name  => $nova_admin_tenant_name,
    nova_user_password      => $nova_user_password,
    nova_db_password        => $nova_db_password,
    enabled_apis            => $nova_enabled_apis,

    rabbit_user             => $rabbit_user,
    rabbit_password         => $rabbit_password,
    rabbit_virtual_host     => $rabbit_virtual_host,
  }

  class { '::quantum':
    verbose               => $verbose,
    debug                 => $verbose,
    core_plugin => 'quantum.plugins.linuxbridge.lb_quantum_plugin.LinuxBridgePluginV2',
    allow_overlapping_ips => true,
    rabbit_user           => $rabbit_user,
    rabbit_password       => $rabbit_password,
    rabbit_virtual_host   => $rabbit_virtual_host,
  }

  class { 'quantum::server':
    auth_tenant => $nova_admin_tenant_name,
    auth_password => $quantum_user_password,
    log_file => 'ssssserver.log'
  }

  class { 'quantum::plugins::linuxbridge':
    sql_connection      => "mysql://quantum:${quantum_db_password}@localhost/quantum?charset=utf8",
    tenant_network_type => 'local',
    network_vlan_ranges => '',
  }

  class { 'quantum::agents::linuxbridge':
    physical_interface_mappings => 'default:eth1', # XXX ????
    # $firewall_driver = 'quantum.agent.linux.iptables_firewall.IptablesFirewallDriver',
  }

  class { 'quantum::agents::dhcp':
    debug => $verbose,
    interface_driver => 'quantum.agent.linux.interface.BridgeInterfaceDriver',
    use_namespaces => false,
  }

  class { 'quantum::agents::metadata':
    debug          => $verbose,
    auth_tenant    => $nova_admin_tenant_name,
    auth_password  => $quantum_user_password,
    shared_secret  => $metadata_shared_secret,
    auth_url       => $auth_url,
    auth_region    => $region,
    metadata_ip    => $controller_address,
  }
  # etc/quantum/plugins/linuxbridge/linuxbridge_conf.ini XXX ?????

  class { 'openstack::cinder::controller':
    verbose            => $verbose,
    keystone_password  => $cinder_user_password,
    rabbit_userid      => $rabbit_user,
    rabbit_password    => $rabbit_password,
    rabbit_host        => $controller_address,
    db_user            => $cinder_db_user,
    db_password        => $cinder_db_password,
  }

  class { 'openstack::horizon':
    django_debug => $verbose,
    secret_key   => $horizon_secret_key,
  }
}






# nothing in compute should need mysql database access!!! 
# that is what nova-conductor is for!!!
node /openstack_compute/ {

    public_interface   => $interface,
    private_interface  => $interface,
    internal_address   => $ipaddress,
    libvirt_type       => 'kvm',
    fixed_range        => $fixed_network_range,
    network_manager    => 'nova.network.manager.FlatDHCPManager',
    multi_host         => true,
    nova_db_password   => $nova_db_password,
    nova_user_password => $nova_user_password,
    quantum_user_password   => $quantum_user_password,
    cinder_db_password      => $cinder_db_password,
    rabbit_host        => $controller_address,
    rabbit_password    => $rabbit_password,
    rabbit_user        => $rabbit_user,

    vncproxy_host      => $controller_address,
    vnc_enabled        => true,
    verbose            => $verbose,
    manage_volumes     => true,
    volume_group       => 'cinder-volumes'

  # Required Network
  $internal_address,
  # Required Nova
  $nova_user_password,
  # Required Rabbit
  $rabbit_password,
  # DB
  $nova_db_password,
  $db_host                       = '127.0.0.1',
  # Nova Database
  $nova_db_user                  = 'nova',
  $nova_db_name                  = 'nova',
  # Network
  $public_interface              = undef,
  $private_interface             = undef,
  $fixed_range                   = undef,
  $network_manager               = 'nova.network.manager.FlatDHCPManager',
  $network_config                = {},
  $multi_host                    = false,
  $enabled_apis                  = 'ec2,osapi_compute,metadata',
  # Quantum
  $quantum                       = true,
  $quantum_user_password         = false,
  $quantum_admin_tenant_name     = 'services',
  $quantum_admin_user            = 'quantum',
  $enable_ovs_agent              = true,
  $enable_l3_agent               = false,
  $enable_dhcp_agent             = false,
  $quantum_auth_url              = "http://127.0.0.1:35357/v2.0",
  $keystone_host                 = '127.0.0.1',
  $quantum_host                  = '127.0.0.1',
  $ovs_local_ip                  = false,
  # Nova
  $nova_admin_tenant_name        = 'services',
  $nova_admin_user               = 'nova',
  $purge_nova_config             = false,
  $libvirt_vif_driver            = 'nova.virt.libvirt.vif.LibvirtGenericVIFDriver',
  # Rabbit
  $rabbit_host                   = '127.0.0.1',
  $rabbit_user                   = 'openstack',
  $rabbit_virtual_host           = '/',
  # Glance
  $glance_api_servers            = false,
  # Virtualization
  $libvirt_type                  = 'kvm',
  # VNC
  $vnc_enabled                   = true,
  $vncproxy_host                 = undef,
  $vncserver_listen              = false,
  # cinder / volumes
  $manage_volumes                = true,
  $cinder_db_password            = false,
  $cinder_db_user                = 'cinder',
  $cinder_db_name                = 'cinder',
  $volume_group                  = 'cinder-volumes',
  $iscsi_ip_address              = '127.0.0.1',
  $setup_test_volume             = false,
  # General



  # resources { 'nova_config':
  #   purge => true,
  # }

  # XXXX make sure nova-conductor is being used and that no DB access is needed from the compute node!
  # $nova_sql_connection = "mysql://${nova_db_user}:${nova_db_password}@${db_host}/${nova_db_name}"

  class { 'nova':
    verbose             => $verbose,
    debug               => $verbose,
    nova_cluster_id     => $nova_cluster_id,
    glance_api_servers  => $glance_api_servers,
    rabbit_host         => $controller_address,
    rabbit_virtual_host => $rabbit_virtual_host,
    rabbit_userid       => $rabbit_user,
    rabbit_password     => $rabbit_password,
    # monitoring_notifications => true,
  }

  class { '::nova::compute':
    enabled                       => true, # XXX defaults to false???
    vncserver_proxyclient_address => $ipaddress,
    vncproxy_host                 => $controller_address,
  }

  class { 'nova::compute::libvirt':
    vncserver_listen  => '0.0.0.0',
    # migration_support => true,
  }

  # XXX expand this out!!!
  class { 'openstack::quantum':
    # Database
    db_host           => $db_host,
    # Networking
    ovs_local_ip      => $ovs_local_ip_real,
    # Rabbit
    rabbit_host       => $rabbit_host,
    rabbit_user       => $rabbit_user,
    rabbit_password   => $rabbit_password,
    # Quantum OVS
    enable_ovs_agent  => $enable_ovs_agent,
    firewall_driver   => false,
    # Quantum L3 Agent
    enable_l3_agent   => $enable_l3_agent,
    enable_dhcp_agent => $enable_dhcp_agent,
    auth_url          => $quantum_auth_url,
    user_password     => $quantum_user_password,
    # Keystone
    keystone_host     => $keystone_host,
    # General
    enabled           => $enabled,
    enable_server     => false,
    verbose           => $verbose,
  }

  class { 'nova::compute::quantum':
    libvirt_vif_driver => $libvirt_vif_driver,
  }

  # Configures nova.conf entries applicable to Quantum.
  class { 'nova::network::quantum':
    quantum_admin_password    => $quantum_user_password,
    quantum_auth_strategy     => 'keystone',
    quantum_url               => "http://${quantum_host}:9696",
    quantum_admin_username    => $quantum_admin_user,
    quantum_admin_tenant_name => $quantum_admin_tenant_name,
    quantum_admin_auth_url    => "http://${keystone_host}:35357/v2.0",
  }

  }

  if $manage_volumes {

    if ! $cinder_db_password {
      fail('cinder_db_password must be set when cinder is being configured')
    }

    $cinder_sql_connection = "mysql://${cinder_db_user}:${cinder_db_password}@${db_host}/${cinder_db_name}"

    class { 'openstack::cinder::storage':
      sql_connection      => $cinder_sql_connection,
      rabbit_password     => $rabbit_password,
      rabbit_userid       => $rabbit_user,
      rabbit_host         => $rabbit_host,
      rabbit_virtual_host => $rabbit_virtual_host,
      volume_group        => $volume_group,
      iscsi_ip_address    => $iscsi_ip_address,
      enabled             => $enabled,
      verbose             => $verbose,
      setup_test_volume   => $setup_test_volume,
      volume_driver       => 'iscsi',
    }

    # set in nova::api
    if ! defined(Nova_config['DEFAULT/volume_api_class']) {
      nova_config { 'DEFAULT/volume_api_class': value => 'nova.volume.cinder.API' }
    }
  }

}
