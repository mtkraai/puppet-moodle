#
define moodle::app (
  $install_dir,
  $install_provider,
  $download_url,
  $moodle_version,
  $default_lang,
  $wwwrooturl,
  $www_owner,
  $www_group,
  $dataroot,
  $dbtype,
  $dbhost,
  $dbname,
  $dbuser,
  $dbpass,
  $dbport,
  $dbsocket,
  $prefix,
  $fullname,
  $shortname,
  $summary,
  $adminuser,
  $adminpass,
  $adminemail,
  Hash $plugins      = {},
) {

  $install_dir_clean = regsubst($install_dir, /\//, '_', 'G')

  if !($install_dir =~ /\/moodle$/) {
    fail("${install_dir} is not valid... install_dir must end with /moodle")
  }

  # manage the moodle data directory
  file { $dataroot:
    ensure  => directory,
    owner   => $www_owner,
    group   => $www_group,
    mode    => '0755',
    seltype => 'httpd_sys_rw_content_t',
  }

  case $install_provider {
    'http': {
      fail('Moodle http install not supported at this time.')
    # # manage the staging class
    # class { 'staging':
    #   path  => '/var/staging',
    # }
    #
    # # download the staged file
    # staging::file { 'moodle.tgz':
    #   source => $download_url,
    # }
    #
    # # ensure that the directory
    # if !defined(File[$install_dir]) {
    #   file { $install_dir:
    #     ensure => directory,
    #     owner  => $www_owner,
    #     group  => $www_group,
    #     mode   => '0755',
    #   }
    # }
    #
    # # get the parent directory... the moodle distribution
    # # gets extracted to a 'moodle' directory
    # $install_parent = getparent($install_dir)
    #
    # staging::extract { 'moodle.tgz':
    #   target  => $install_parent,
    #   user    => $www_owner,
    #   group   => $www_group,
    #   creates => "${install_dir}/install.php",
    #   require => [Staging::File['moodle.tgz'],File[$install_dir, $dataroot]],
    # }
    }
    'git': {
      $stripped_version = $moodle_version.split('\.')[0,2].join()
      $git_branch = $moodle_version ? {
        /^\d+\.\d+$/  => "MOODLE_${stripped_version}_STABLE",
        /^\d\d+$/     => "MOODLE_${stripped_version}_STABLE",
        default       => $moodle_version,
      }

      vcsrepo { "moodle-${install_dir}":
        ensure   => 'latest',
        provider => 'git',
        path     => $install_dir,
        source   => $download_url,
        revision => $git_branch,
        depth    => 1,
        owner    => $www_owner,
        group    => $www_group,
      }
      concat { "git-exclude-${install_dir}":
        path           => "${install_dir}/.git/info/exclude",
        ensure_newline => true,
        owner          => $www_owner,
        group          => $www_group,
        mode           => '0644',
        warn           => "# This file is managed by Puppet. DO NOT EDIT.\n",
      }
      concat::fragment { "git-exclude-${install_dir}-${title}":
        target  => "git-exclude-${install_dir}",
        content => "\n# Directories of installed plugins",
        order   => '09',
      }
      $plugin_defaults = {
        'install_provider'   => 'git',
        'moodle_install_dir' => $install_dir,
        'plugin_version'     => $moodle_version,
        'www_owner'          => $www_owner,
        'www_group'          => $www_group,
      }
      $plugins.each |$plugname, $plugparams| {
        moodle::plugin { "moodle-${install_dir}-${plugname}":
          name => $plugname,
          tag  => ["moodle-${install_dir_clean}"],
          *    => $plugin_defaults + $plugparams,
        }
      }
    }
  }

  # run the moodle cli installer in non-interactive mode. the parameters for the installer
  # are configured in the template install_cmd.erb (to make variable substitution easier)
  exec { "run-installer-${install_dir}":
    command   => template('moodle/install_cmd.erb'),
    user      => $www_owner,
    group     => $www_group,
    logoutput => true,
    path      => '/usr/bin:/usr/local/bin',
    creates   => "${install_dir}/config.php",
  }

  exec { "run-updater-${install_dir}":
    command     => "php ${install_dir}>/admin/cli/upgrade.php --non-interactive",
    user        => $www_owner,
    group       => $www_group,
    logoutput   => true,
    path        => '/usr/bin:/usr/local/bin',
    refreshonly => true,
  }

  cron { "moodle-${install_dir}":
    command     => '/usr/bin/php /var/www/moodle/admin/cli/cron.php',
    user        => $www_owner,
  }

  $repo_res = Vcsrepo["moodle-${install_dir}"]
  $repo_res                                                 ->
  Moodle::Plugin <| tag == "moodle-${install_dir_clean}" |> ->
  Exec["run-installer-${install_dir}"]                      ->
  Exec["run-updater-${install_dir}"]                        ->
  Cron["moodle-${install_dir}"]

  $repo_res                            ~>
  Exec["run-updater-${install_dir}"]
}
