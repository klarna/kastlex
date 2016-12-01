%define debug_package %{nil}
%define _service      %{_name}
%define _user         %{_name}
%define _group        %{_name}
%define _conf_dir     %{_sysconfdir}/%{_service}
%define _log_dir      %{_var}/log/%{_service}

Summary: %{_description}
Name: %{_name}
Version: %{_version}
Release: %{_release_version}%{?dist}
License: Apache License, Version 2.0
URL: https://github.com/klarna/kastlex
BuildRoot: %{_tmppath}/%{_name}-%{_version}-root
Vendor: Klarna AB
Packager: Ivan Dyachkov <ivan.dyachkov@klarna.com>
Provides: %{_service}
BuildRequires: systemd
%systemd_requires

%description
%{_description}

%prep

%build
mix deps.get
MIX_ENV=prod mix release --env=prod --no-tar

%install
mkdir -p %{buildroot}%{_prefix}
mkdir -p %{buildroot}%{_log_dir}
mkdir -p %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_conf_dir}
mkdir -p %{buildroot}%{_sysconfdir}/sysconfig
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_sharedstatedir}/%{_service}
cp -r rel/%{_name} %{buildroot}%{_prefix}/

cat > %{buildroot}%{_unitdir}/%{_service}.service <<EOF
[Unit]
Description=%{_description}
After=network.target

[Service]
User=%{_user}
Group=%{_group}
Restart=on-failure
EnvironmentFile=%{_sysconfdir}/sysconfig/%{_service}
ExecStart=%{_prefix}/%{_name}/bin/%{_name} foreground

[Install]
WantedBy=multi-user.target
EOF

cat > %{buildroot}%{_conf_dir}/permissions.yml <<EOF
anonymous:
  list_topics: true
  show_topic: all
  list_brokers: true
  show_broker: all
  show_offsets: all
  fetch: all
  list_urps: true
  show_urps: all
  list_groups: true
  show_group: all
admin:
  reload: true
EOF

cat > %{buildroot}%{_conf_dir}/passwd.yml <<EOF
admin:
  password_hash: "$2b$12$gp5pJc/AGclJradJC9DuHe6xJoIe5HOwtAUGe2z7QFeAjvw1eZUKW"
EOF

cat > %{buildroot}%{_sysconfdir}/sysconfig/%{_service} <<EOF
RELEASE_MUTABLE_DIR=%{_sharedstatedir}/%{_service}
RUNNER_LOG_DIR=%{_log_dir}
KASTLEX_KAFKA_CLUSTER=localhost:9092
KASTLEX_ZOOKEEPER_CLUSTER=localhost:2181
KASTLEX_HTTP_PORT=8092
KASTLEX_PERMISSIONS_FILE_PATH=%{_conf_dir}/permissions.yml
KASTLEX_PASSWD_FILE_PATH=%{_conf_dir}/passwd.yml
KASTLEX_USE_HTTPS=false
KASTLEX_CACERTFILE=%{_conf_dir}/ssl/ca-cert.crt
KASTLEX_CERTFILE=%{_conf_dir}/ssl/server.crt
KASTLEX_KEYFILE=%{_conf_dir}/ssl/server.key
#KASTLEX_JWK_FILE=
EOF

cat > %{buildroot}/%{_bindir}/%{_service} <<EOF
#!/bin/sh
set -a
source %{_sysconfdir}/sysconfig/%{_service}
set +a
if [ \$# -eq 0 ]; then
    %{_prefix}/%{_name}/bin/%{_name} remote_console
else
    %{_prefix}/%{_name}/bin/%{_name} \$@
fi
EOF

%clean
rm -rf $RPM_BUILD_ROOT

%pre
if [ $1 = 1 ]; then
  # Initial installation
  /usr/bin/getent group %{_group} >/dev/null || /usr/sbin/groupadd -r %{_group}
  if ! /usr/bin/getent passwd %{_user} >/dev/null ; then
      /usr/sbin/useradd -r -g %{_group} -m -d %{_sharedstatedir}/%{_service} -c "%{_service}" %{_user}
  fi
fi

%post
%systemd_post %{_service}.service

%preun
%systemd_preun %{_service}.service

%postun
%systemd_postun

%files
%defattr(-,root,root)
%{_prefix}/%{_name}
%attr(0755,root,root) %{_bindir}/%{_service}
%{_unitdir}/%{_service}.service
%config(noreplace) %{_conf_dir}/*
%config(noreplace) %{_sysconfdir}/sysconfig/%{_service}
%attr(0700,%{_user},%{_group}) %dir %{_sharedstatedir}/%{_service}
%attr(0755,%{_user},%{_group}) %dir %{_log_dir}
