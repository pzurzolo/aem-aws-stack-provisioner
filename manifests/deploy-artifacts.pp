File {
  backup => false,
}

class deploy_artifacts (
  $tmp_dir,
  $descriptor_file     = $::descriptor_file,
  $component           = $::component,
  $apache_conf_dir     = $::apache_conf_dir,
  $dispatcher_conf_dir = $::dispatcher_conf_dir,
  $static_assets_dir   = $::static_assets_dir,
  $virtual_hosts_dir   = $::virtual_hosts_dir,
  $retries_max_tries          = 60,
  $retries_base_sleep_seconds = 5,
  $retries_max_sleep_seconds  = 5,
) {

  Aem_aem {
    retries_max_tries          => $retries_max_tries,
    retries_base_sleep_seconds => $retries_base_sleep_seconds,
    retries_max_sleep_seconds  => $retries_max_sleep_seconds,
  }

  # Load descriptor file
  $descriptor_hash = loadjson("${tmp_dir}/${descriptor_file}")

  # Retrieve component hash, if empty then there's no artifact to deploy
  $component_hash = $descriptor_hash[$component]
  notify { "Component descriptor: ${component_hash}": }

  if $component_hash {

    # Deploy AEM Dispatcher artifacts
    $artifacts = $component_hash['artifacts']
    if $artifacts {
      notify { "AEM Dispatcher artifacts to deploy: ${artifacts}": }
      class { 'deploy_dispatcher_artifacts':
        artifacts => $artifacts,
        path      => "${tmp_dir}/artifacts",
      }
    } else {
      notify { "No artifacts defined for component: ${component} in descriptor file: ${descriptor_file}. No Dispatcher artifacts to deploy": }
    }

    # Deploy Author/Publish AEM packages
    $packages = $component_hash['packages']
    if $packages {
      notify { "AEM packages to deploy: ${packages}": }
      aem_resources::deploy_packages { 'Deploy packages':
        packages => $packages,
        path     => "${tmp_dir}/packages",
      }
    } else {
      notify { "No packages defined for component: ${component} in descriptor file: ${descriptor_file}. No AEM package to deploy": }
    }

  } else {
    notify { "Component: ${component} not found in descriptor file: ${descriptor_file}. Nothing to deploy.": }
  }
}

class deploy_dispatcher_artifacts (
  $artifacts,
  $path,
  $apache_conf_dir     = '/etc/httpd/conf',
  $dispatcher_conf_dir = '/etc/httpd/conf.d',
  $static_assets_dir   = '/var/www/html',
  $virtual_hosts_dir   = '/etc/httpd/conf.d',
) {

  # Load artifacts-descriptor file - generated by the aem-tools/generate-artifacts-descriptor.py, which is called by aem-tools/download-artifacts.pp
  # artifacts-descriptor file is needed because Puppet can't easily traverse through a directory structure
  $artifacts_descriptor_hash = loadjson("${path}/artifacts-descriptor.json")
  notify { "Artifacts-Descriptor: ${artifacts_descriptor_hash}": }

  # Extract the list of artifacts to be deployed
  $artifacts_descriptor_array = $artifacts_descriptor_hash['children']
  notify { "Dispatcher artifacts to deploy: ${artifacts_descriptor_array}": }

  $artifacts.each | Integer $index, Hash $artifact| {
    $artifacts_descriptor_array.each | Integer $artifact_details_index, Hash $artifact_details| {

      if $artifact_details['name'] == $artifact['name'] {

        # Extract artifact_details_content array
        $artifact_details_contents = $artifact_details['children']
        notify { "Artifact details: ${artifact_details_contents}": }

        $artifact_details_contents.each | Integer $artifact_details_content_index, Hash $artifact_details_content| {

          # Process Apache configuration templates
          if $artifact_details_content['name'] == 'apache-conf-templates' {
            $artifact_details_content['children'].each | Integer $apache_conf_template_index, Hash $apache_conf_template| {
              file { regsubst("${apache_conf_dir}/${apache_conf_template[name]}", '.epp', '', 'G'):
                ensure  => file,
                content => epp("${path}/${artifact[name]}/apache-conf-templates/${apache_conf_template[name]}", {'conf_dir' => $dispatcher_conf_dir}),
                owner   => 'root',
                group   => 'root',
                mode    => '0644',
                notify  => Exec['graceful restart'],
              }
            }
          }

          # Process Virtual Hosts configuration templates
          if $artifact_details_content['name'] == 'virtual-hosts-templates' {

            # Ensure default files from OS and created AMI are cleaned up
            $default_files = [
              "${dispatcher_conf_dir}/15-default.conf",
              "${dispatcher_conf_dir}/1-puppet-aem-resources.conf"
            ]
            $default_files.each |Integer $index, String $default_file | {
              file { $default_file:
                ensure => absent,
                before => Exec['graceful restart'],
              }
            }

            $artifact_details_content['children'].each | Integer $virtual_host_template_index, Hash $virtual_host_template| {

              # Create sub directory under virtual hosts directory
              # Create virtual hosts configuration files underneath the sub-directory
              # This unfortunately only handles one level of sub-directory, needs
              # to be improved when aem-tools Puppet files are replaced by proper
              # application
              if $virtual_host_template['type'] == 'directory' {

                file { "${virtual_hosts_dir}/${virtual_host_template[name]}":
                  ensure => directory,
                  owner  => 'root',
                  group  => 'root',
                  mode   => '0755',
                }

                $virtual_host_template['children'].each | Integer $virtual_host_site_template_index, Hash $virtual_host_site_template| {
                  file { regsubst("${virtual_hosts_dir}/${virtual_host_template[name]}/${virtual_host_site_template[name]}", '.epp', '', 'G'):
                    ensure  => file,
                    content => epp("${path}/${artifact[name]}/virtual-hosts-templates/${virtual_host_template[name]}/${virtual_host_site_template[name]}"),
                    owner   => 'root',
                    group   => 'root',
                    mode    => '0644',
                    require => File["/etc/httpd/conf.d/${virtual_host_template[name]}"],
                    notify  => Exec['graceful restart'],
                  }
                }
              }

              # Create virtual hosts configuration files underneath virtual hosts directory
              elsif $virtual_host_template['type'] == 'file' {
                file { regsubst("${virtual_hosts_dir}/${virtual_host_template[name]}", '.epp', '', 'G'):
                  ensure  => file,
                  content => epp("${path}/${artifact[name]}/virtual-hosts-templates/${virtual_host_template[name]}"),
                  owner   => 'root',
                  group   => 'root',
                  mode    => '0644',
                  notify  => Exec['graceful restart'],
                }
              }

            }
          }

          # Process Dispatcher configuration templates
          if $artifact_details_content[name] == 'dispatcher-conf-templates' {
            $artifact_details_content['children'].each | Integer $dispatcher_conf_template_index, Hash $dispatcher_conf_template| {
              file { regsubst("${dispatcher_conf_dir}/${dispatcher_conf_template[name]}", '.epp', '', 'G'):
                ensure  => file,
                content => epp("${path}/${artifact[name]}/dispatcher-conf-templates/${dispatcher_conf_template[name]}", {conf_dir => $dispatcher_conf_dir}),
                owner   => 'root',
                group   => 'root',
                mode    => '0644',
                notify  => Exec['graceful restart'],
              }
            }
          }

          # Process static aem_password_reset_version
          if $artifact_details_content[name] == 'static-assets' {
            file { 'Copy static assets':
               path    => $static_assets_dir,
               source  => "${path}/${artifact[name]}/static-assets",
               recurse => true,
            }
          }

        }
      }
    }
  }

  # Gracefully restart Apache httpd, called after each Dispatcher artifact deployment
  exec { 'graceful restart':
    cwd         => '/usr/sbin',
    path        => '/usr/sbin',
    command     => 'apachectl -k graceful',
    refreshonly => true,
  }



}

include deploy_artifacts
