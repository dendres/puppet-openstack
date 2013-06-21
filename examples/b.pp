
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
# parted /dev/sdb mkpart primary 1 100%
# vgcreate cinder-volumes /dev/sdb1
#
# apt-get install puppet rake git
# puppet module install puppetlabs-firewall
# gem install bundler
#
# git clone into /etc/puppet/modules/openstack
# cd /etc/puppet/modules/openstack
# bundle install --path=vendor/bundle
# bundle exec rake -T
# bundle exec rake modules:clone
# puppet apply --modulepath /etc/puppet/modules site.pp --certname openstack_controller
# puppet apply --modulepath /etc/puppet/modules site.pp --certname openstack_compute
#

# in this example we have 2 hosts with identical network configuration
# $ipaddress fact is available and referrs to the only IP configured on each server
$interface               = 'em1'

# the compute node will need to know which host is the controller:
$controller_address      = '10.10.12.15'
$fixed_network_range     = '10.10.14.0/24'

$verbose                 = true
$region                  = 'RegionOne'
$mysql_root_password     = 'sql_pass'
$keystone_admin_email    = 'root@localhost'  # 'admin' user in keystone
$keystone_admin_password = 'keystone_admin'
$keystone_admin_tenant   = 'admin'
$keystone_db_password    = 'keystone_db_pass'
$keystone_admin_token    = 'keystone_admin_token'
$cinder_db_password      = 'cinder_pass'
$cinder_user_password    = 'cinder_pass'
$glance_db_password      = 'glance_pass'
$glance_user_password    = 'glance_pass'
$nova_admin_tenant_name  = 'services'
$nova_db_password        = 'nova_pass'
$nova_user_password      = 'nova_pass'
$nova_cluster_id         = 'localcluster'
$quantum_db_password     = 'quantum_pass'
$quantum_user_password   = 'quantum_pass'
$metadata_shared_secret  = 'metadata_shared_secret'
$rabbit_virtual_host     = '/'
$rabbit_user             = 'openstack_rabbit_user'
$rabbit_password         = 'openstack_rabbit_password'
$horizon_secret_key      = 'horizon_secret_key'
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
    admin_email           => $keystone_admin_email,
    admin_password        => $keystone_admin_password,

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
    enabled_apis            => 'ec2,osapi_compute,metadata'

    rabbit_user             => $rabbit_user,
    rabbit_password         => $rabbit_password,
    rabbit_virtual_host     => $rabbit_virtual_host,
  }

  class { '::quantum':
    verbose               => $verbose,
    debug                 => $verbose,
    core_plugin => 'quantum.plugins.linuxbridge.lb_quantum_plugin.LinuxBridgePluginV2',
    allow_overlapping_ips => true,
    rabbit_host           => '127.0.0.1',
    rabbit_user           => $rabbit_user,
    rabbit_password       => $rabbit_password,
    rabbit_virtual_host   => $rabbit_virtual_host,
  }

  class { 'quantum::server':
    auth_tenant => $nova_admin_tenant_name,
    auth_password => $quantum_user_password,
    log_file => '/var/log/quantum/ssssserver.log'
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
    # debug => $verbose,
    interface_driver => 'quantum.agent.linux.interface.BridgeInterfaceDriver',
    use_namespaces => false,
  }

  class { 'quantum::agents::metadata':
    # debug          => $verbose,
    auth_tenant    => $nova_admin_tenant_name,
    auth_password  => $quantum_user_password,
    shared_secret  => $metadata_shared_secret,
    auth_url       => $auth_url,
    auth_region    => $region,
    metadata_ip    => $controller_address,
  }
  # etc/quantum/plugins/linuxbridge/linuxbridge_conf.ini XXX ?????

  # XXX break this up!!
  class { 'openstack::cinder::controller':
    verbose            => $verbose,
    keystone_password  => $cinder_user_password,
    rabbit_userid      => $rabbit_user,
    rabbit_password    => $rabbit_password,
    rabbit_host        => '127.0.0.1',
    db_user            => $cinder_db_user,
    db_password        => $cinder_db_password,
  }

  class { '::horizon':
    quantum          => false,
    secret_key       => $horizon_secret_key,
    django_debug     => 'True',
  }

  class { 'memcached':
    listen_ip => '127.0.0.1',
  }

  file { '/var/run/memcached.pid':
    ensure => present,
    owner => 'nobody',
  }
}







# nothing in compute should need mysql database access!!!
# that is what nova-conductor is for!!!
node /openstack_compute/ {

  # resources { 'nova_config':
  #   purge => true,
  # }

  # XXXX make sure nova-conductor is being used and that no DB access is needed from the compute node!
  # $nova_sql_connection = "mysql://${nova_db_user}:${nova_db_password}@${db_host}/${nova_db_name}"

  class { 'nova':
    verbose             => $verbose,
    # debug               => $verbose,
    nova_cluster_id     => $nova_cluster_id,
    glance_api_servers  => "${controller_address}:9292",
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

  class { 'nova::compute::quantum':
    libvirt_vif_driver => 'nova.virt.libvirt.vif.LibvirtGenericVIFDriver',
  }

  class { 'nova::network::quantum':
    quantum_admin_password    => $quantum_user_password,
    quantum_admin_tenant_name => $nova_admin_tenant_name,
    quantum_url               => "http://${controller_address}:9696",
    quantum_admin_auth_url    => "http://${controller_address}:35357/v2.0",
  }

  class { '::quantum':
    verbose               => $verbose,
    # debug                 => $verbose,
    core_plugin => 'quantum.plugins.linuxbridge.lb_quantum_plugin.LinuxBridgePluginV2',
    allow_overlapping_ips => true,
    rabbit_user           => $rabbit_user,
    rabbit_password       => $rabbit_password,
    rabbit_virtual_host   => $rabbit_virtual_host,
  }

  # XXX cinder something on compute node ????
}




