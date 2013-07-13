
#
# openstack E
# - controller server
# - compute server
# - single physical interface on each server
# - flat single vlan
# - nova-network linux bridge
# - NO: quantum, cinder, swift, horizon
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

$enabled_apis            = 'ec2,osapi_compute,metadata',

$verbose                 = true
$debug                   = true
$region                  = 'RegionOne'
$mysql_root_password     = 'sql_pass'
$keystone_admin_email    = 'root@localhost'  # 'admin' user in keystone
$keystone_admin_password = 'keystone_admin'
$keystone_admin_tenant   = 'admin'
$keystone_db_password    = 'keystone_db_pass'
$keystone_admin_token    = 'keystone_admin_token'

$glance_db_password      = 'glance_pass'
$glance_user_password    = 'glance_pass'

$nova_admin_tenant_name  = 'services'
$nova_db_password        = 'nova_pass'
$nova_user_password      = 'nova_pass'
$nova_cluster_id         = 'localcluster'

$metadata_shared_secret  = 'metadata_shared_secret'

$rabbit_virtual_host     = '/'
$rabbit_user             = 'openstack_rabbit_user'
$rabbit_password         = 'openstack_rabbit_password'

$floating_network_range  = false
$auto_assign_floating_ip = false


class { 'openstack::test_file': }

class { 'openstack::auth_file':
    admin_password       => $keystone_admin_password,
    keystone_admin_token => $keystone_admin_token,
    controller_node      => $controller_node_internal,
}

node /openstack_controller/ {
    Class['openstack::db::mysql'] -> Class['openstack::keystone']
    Class['openstack::db::mysql'] -> Class['openstack::nova::controller']
    Class['openstack::db::mysql'] -> Class['openstack::glance']
    Class['glance::db::mysql']    -> Class['glance::registry']

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

    $keystone_sql_conn = "mysql://keystone:${keystone_db_password}@localhost/keystone"

    class { '::keystone':
        verbose        => $verbose,
        debug          => $debug,
        admin_token    => $keystone_admin_token,
        sql_connection => $keystone_sql_conn,
    }

    class { 'keystone::roles::admin':
        email        => $keystone_admin_email,
        password     => $keystone_admin_password,
        admin_tenant => $keystone_admin_tenant,
    }

    class { 'keystone::endpoint':
        public_address   => $ipaddress,
        admin_address    => $ipaddress,
        internal_address => $ipaddress,
        region           => $region,
    }

    class { 'glance::keystone::auth':
        password         => $glance_user_password,
        public_address   => $ipaddress,
        admin_address    => $ipaddress,
        internal_address => $ipaddress,
        region           => $region,
    }

    class { 'nova::keystone::auth':
        password         => $nova_user_password,
        public_address   => $ipaddress,
        admin_address    => $ipaddress,
        internal_address => $ipaddress,
        region           => $region,
        cinder           => false,
    }

    $glance_sql_conn = "mysql://glance:${glance_db_password}@localhost/glance"

    class { 'glance::api':
        verbose           => $verbose,
        debug             => $debug,
        auth_host         => '127.0.0.1',
        keystone_tenant   => $nova_admin_tenant_name,
        keystone_user     => 'glance',
        keystone_password => $glance_user_password,
        sql_connection    => $glance_sql_conn,
    }

    class { 'glance::registry':
        verbose           => $verbose,
        debug             => $debug,
        auth_host         => '127.0.0.1',
        keystone_tenant   => $nova_admin_tenant_name,
        keystone_user     => 'glance',
        keystone_password => $glance_user_password,
        sql_connection    => $glance_sql_conn,
    }

    class { 'glance::backend::file':
        filesystem_store_datadir => '/var/lib/glance/images/'
    }

    class { 'nova::rabbitmq':
        userid        => $rabbit_user,
        password      => $rabbit_password,
        virtual_host  => $rabbit_virtual_host,
    }

    $nova_sql_conn = "mysql://nova:${nova_db_password}@localhost/nova"

    class { 'nova':
        verbose              => $verbose,
        debug                => $debug,
        sql_connection       => $nova_sql_conn,
        rabbit_userid        => $rabbit_user,
        rabbit_password      => $rabbit_password,
        rabbit_virtual_host  => $rabbit_virtual_host,
        rabbit_host          => 'localhost',
    }

    class { 'nova::api':
        admin_tenant_name => $nova_admin_tenant_name,
        admin_password    => $nova_user_password,
        enabled_apis      => $enabled_apis,
        # quantum_metadata_proxy_shared_secret => $metadata_shared_secret,
    }

    # http://docs.openstack.org/trunk/openstack-compute/admin/content/existing-ha-networking-options.html
    # if $multi_host {
    # nova_config { 'DEFAULT/multi_host': value => true }
    # $enable_network_service = false

    class { 'nova::network':
        private_interface => $interface,
        public_interface  => $interface,
        fixed_range       => $fixed_network_range,
        enabled           => true,
    }

    class { [
             'nova::scheduler',
             'nova::objectstore',
             'nova::cert',
             'nova::consoleauth',
             'nova::conductor'
             ]: enabled => true,
    }

    class { 'nova::vncproxy':
        host    => $controller_address,
        enabled => true,
    }

    class { 'memcached':
        listen_ip => '127.0.0.1',
    }

    file { '/var/run/memcached.pid':
        ensure => present,
        owner => 'nobody',
    }
}

node /openstack_compute/ {

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
}
















