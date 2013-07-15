
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
# cd /etc/puppet/modules
# git clone git@github.com:dendres/puppet-openstack.git
# mv puppet-openstack openstack
# cd openstack
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

$enabled_apis            = 'ec2,osapi_compute,metadata'

$verbose                 = true
$debug                   = true
$region                  = 'RegionOne'
$mysql_root_password     = 'sql_pass'
$mysql_allowed_hosts     = '%'

# pattern: ${service}_db_username = ${service}
# XXX propagate this pattern!!!!

$admin_tenant            = 'admin'
$services_tenant         = 'services'

$keystone_admin_email    = 'root@localhost'  # 'admin' user in keystone
$keystone_admin_password = 'keystone_pass'

$keystone_db_password    = 'keystone_db_pass'
$keystone_admin_token    = 'keystone_admin_token'

$glance_db_password      = 'glance_db_pass'
$glance_user_password    = 'glance_user_pass'

$nova_db_password        = 'nova_db_pass'
$nova_user_password      = 'nova_user_pass'

$nova_cluster_id         = 'test_e_cluster'
$metadata_shared_secret  = 'metadata_shared_secret'

$rabbit_virtual_host     = '/'
$rabbit_user             = 'rabbit_user'
$rabbit_password         = 'rabbit_password'

$floating_network_range  = false
$auto_assign_floating_ip = false


class { 'openstack::test_file': }

class { 'openstack::auth_file':
    admin_password       => $keystone_admin_password,
    keystone_admin_token => $keystone_admin_token,
    controller_node      => $controller_node_internal,
}

node /openstack_controller/ {

    class { 'memcached':
        listen_ip => '127.0.0.1',
    }

    file { '/var/run/memcached.pid':
        ensure => present,
        owner => 'nobody',
    }

    class { 'mysql::server':
        config_hash => {
            'root_password' => $mysql_root_password,
            'bind_address'  => '127.0.0.1',
        }
    }

    class { 'mysql::server::account_security': }

    $keystone_sql_conn = "mysql://keystone:${keystone_db_password}@localhost/keystone"

    class { 'keystone::db::mysql':
        user          => 'keystone', # default = keystone_admin ?
        password      => $keystone_db_password,
        allowed_hosts => $mysql_allowed_hosts,
    }

    class { '::keystone':
        verbose        => $verbose,
        debug          => $debug,
        admin_token    => $keystone_admin_token,
        sql_connection => $keystone_sql_conn,
    }

    class { 'keystone::roles::admin':
        email        => $keystone_admin_email,
        password     => $keystone_admin_password,
        admin_tenant => $admin_tenant,
    }

    class { 'keystone::endpoint':
        public_address   => $ipaddress,
        admin_address    => $ipaddress,
        internal_address => $ipaddress,
        region           => $region,
    }

    $glance_sql_conn = "mysql://glance:${glance_db_password}@localhost/glance"

    Class['glance::db::mysql'] -> Class['glance::registry']

    class { 'glance::db::mysql':
        password      => $glance_db_password,
        allowed_hosts => $mysql_allowed_hosts,
    }

    class { 'glance::keystone::auth':
        password         => $glance_user_password,
        public_address   => $ipaddress,
        admin_address    => $ipaddress,
        internal_address => $ipaddress,
        region           => $region,
    }

    class { 'glance::registry':
        verbose           => $verbose,
        debug             => $debug,
        auth_host         => '127.0.0.1',
        keystone_tenant   => $services_tenant,
        keystone_user     => 'glance',
        keystone_password => $glance_user_password,
        sql_connection    => $glance_sql_conn,
    }

    class { 'glance::backend::file':
        filesystem_store_datadir => '/var/lib/glance/images/'
    }

    class { 'glance::api':
        verbose           => $verbose,
        debug             => $debug,
        auth_host         => '127.0.0.1',
        keystone_tenant   => $services_tenant,
        keystone_user     => 'glance',
        keystone_password => $glance_user_password,
        sql_connection    => $glance_sql_conn,
    }

    $nova_sql_conn = "mysql://nova:${nova_db_password}@localhost/nova"

    class { 'nova::db::mysql':
      password      => $nova_db_password,
      allowed_hosts => $mysql_allowed_hosts,
    }

    class { 'nova::rabbitmq':
        userid        => $rabbit_user,
        password      => $rabbit_password,
        virtual_host  => $rabbit_virtual_host,
    }

    class { 'nova::keystone::auth':
        password         => $nova_user_password,
        public_address   => $ipaddress,
        admin_address    => $ipaddress,
        internal_address => $ipaddress,
        region           => $region,
        cinder           => false,
    }

    class { 'nova':
        verbose              => $verbose,
        debug                => $debug,
        nova_cluster_id      => $nova_cluster_id,
        sql_connection       => $nova_sql_conn,
        rabbit_userid        => $rabbit_user,
        rabbit_password      => $rabbit_password,
        rabbit_virtual_host  => $rabbit_virtual_host,
        rabbit_host          => 'localhost',
    }

    class { 'nova::api':
        admin_tenant_name => $services_tenant,
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














