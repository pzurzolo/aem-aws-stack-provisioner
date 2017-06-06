class author_standby (
  $base_dir,
  $tmp_dir,
  $puppet_conf_dir,
  $crx_quickstart_dir,
  $author_protocol,
  $author_port,
  $aem_repo_device,
) {

  class { 'aem_resources::puppet_aem_resources_set_config':
    conf_dir => "${puppet_conf_dir}",
    protocol => "${author_protocol}",
    host     => 'localhost',
    port     => "${author_port}",
    debug    => true,
  }
  -> class { 'aem_resources::author_standby_set_config':
    crx_quickstart_dir => "${crx_quickstart_dir}",
    primary_host       => "${::authorprimaryhost}",
  }
  -> file { "${crx_quickstart_dir}/repository/index/":
    ensure  => absent,
    recurse => true,
    purge   => true,
    force   => true,
  }
  -> service { 'aem-aem':
    ensure => 'running',
    enable => true,
  }

  file_line { 'Set the collectd cloudwatch proxy_server_name':
    path   => '/opt/collectd-cloudwatch/src/cloudwatch/config/plugin.conf',
    line   => "proxy_server_name = \"${::proxy_protocol}://${::proxy_host}\"",
    match  => '^#proxy_server_name =.*$',
    notify => Service['collectd'],
  }

  file_line { 'Set the collectd cloudwatch proxy_server_port':
    path   => '/opt/collectd-cloudwatch/src/cloudwatch/config/plugin.conf',
    line   => "proxy_server_port = \"${::proxy_port}\"",
    match  => '^#proxy_server_port =.*$',
    notify => Service['collectd'],
  }

  collectd::plugin::genericjmx::mbean {
    'garbage_collector':
      object_name     => 'java.lang:type=GarbageCollector,*',
      instance_prefix => 'gc-',
      instance_from   => 'name',
      values          => [
        {
          'type'    => 'invocations',
          table     => false,
          attribute => 'CollectionCount',
        },
        {
          'type'          => 'total_time_in_ms',
          instance_prefix => 'collection_time',
          table           => false,
          attribute       => 'CollectionTime',
        },
      ];
    'memory-heap':
      object_name     => 'java.lang:type=Memory',
      instance_prefix => 'memory-heap',
      values          => [
        {
          'type'    => 'jmx_memory',
          table     => true,
          attribute => 'HeapMemoryUsage',
        },
      ];
    'memory-nonheap':
      object_name     => 'java.lang:type=Memory',
      instance_prefix => 'memory-nonheap',
      values          => [
        {
          'type'    => 'jmx_memory',
          table     => true,
          attribute => 'NonHeapMemoryUsage',
        },
      ];
    'memory-permgen':
      object_name     => 'java.lang:type=MemoryPool,name=*Perm Gen',
      instance_prefix => 'memory-permgen',
      values          => [
        {
          'type'    => 'jmx_memory',
          table     => true,
          attribute => 'Usage',
        },
      ];
    'standby-status':
      object_name     => 'org.apache.jackrabbit.oak:*,name=Status,type=*Standby*',
      instance_prefix => "${::stackprefix}-standby-status",
      values          => [
        {
          instance_prefix => 'seconds_since_last_success',
          mbean_type      => 'delay',
          table           => false,
          attribute       => 'SecondsSinceLastSuccess',
        },
      ];
  }

  file_line { 'seconds_since_last_success standby status':
    ensure => present,
    line   => "GenericJMX-${::stackprefix}-standby-status-delay-seconds_since_last_success",
    path   => '/opt/collectd-cloudwatch/src/cloudwatch/config/whitelist.conf',
  }

  collectd::plugin::genericjmx::connection { 'aem':
    host        => $::fqdn,
    service_url => 'service:jmx:rmi:///jndi/rmi://localhost:8463/jmxrmi',
    collect     => [ 'standby-status' ],
  }

  class { '::collectd':
    service_ensure => running,
    service_enable => true,
  }

  # Set up AEM tools
  file { "${base_dir}/aem-tools/":
    ensure => directory,
    mode   => '0775',
    owner  => 'root',
    group  => 'root',
  }
  -> file { "${base_dir}/aem-tools/deploy-artifact.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/deploy-artifact.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }
  -> file { "${base_dir}/aem-tools/deploy-artifacts.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/deploy-artifacts.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }
  -> file { "${base_dir}/aem-tools/export-backup.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/export-backup.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }
  -> file { "${base_dir}/aem-tools/import-backup.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/import-backup.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }
  -> file { "${base_dir}/aem-tools/promote-author-standby-to-primary.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/promote-author-standby-to-primary.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }
  -> file {"${base_dir}/aem-tools/crx-process-quited.sh":
    ensure => present,
    source => "file://${base_dir}/aem-aws-stack-provisioner/files/aem-tools/crx-process-quited.sh",
    mode   => '0775',
    owner  => 'root',
    group  => 'root',
  }
  -> file {"${base_dir}/aem-tools/oak-run-process-quited.sh":
    ensure => present,
    source => "file://${base_dir}/aem-aws-stack-provisioner/files/aem-tools/oak-run-process-quited.sh",
    mode   => '0775',
    owner  => 'root',
    group  => 'root',
  }

  archive { "${base_dir}/aem-tools/oak-run-${::oak_run_version}.jar":
    ensure => present,
    source => "s3://${::data_bucket}/${::stackprefix}/oak-run-${::oak_run_version}.jar",
  }
  -> file { "${base_dir}/aem-tools/offline-compaction.sh":
    ensure  => present,
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
    content => epp(
      "${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/offline-compaction.sh.epp",
      {
        'base_dir'           => "${base_dir}",
        'oak_run_version'    => "${::oak_run_version}",
        'crx_quickstart_dir' => $crx_quickstart_dir,
      }
    ),
  }

  file { "${base_dir}/aem-tools/export-backups.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/export-backups.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }

  file { "${base_dir}/aem-tools/enable-crxde.sh":
    ensure  => present,
    content => epp("${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/enable-crxde.sh.epp", { 'base_dir' => "${base_dir}" }),
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
  }

  file { "${base_dir}/aem-tools/live-snapshot-backup.sh":
    ensure  => present,
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
    content => epp(
      "${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/live-snapshot-backup.sh.epp",
      {
        'base_dir'        => "${base_dir}",
        'aem_repo_device' => "${aem_repo_device}",
        'component'       => "${::component}",
        'stack_prefix'    => "${::stackprefix}",
      }
    ),
  }

  file { "${base_dir}/aem-tools/offline-snapshot-backup.sh":
    ensure  => present,
    mode    => '0775',
    owner   => 'root',
    group   => 'root',
    content => epp(
      "${base_dir}/aem-aws-stack-provisioner/templates/aem-tools/offline-snapshot-backup.sh.epp",
      {
        'base_dir'        => "${base_dir}",
        'aem_repo_device' => "${aem_repo_device}",
        'component'       => "${::component}",
        'stack_prefix'    => "${::stackprefix}",
      }
    ),
  }

}

include author_standby
