def set_session_user(user)
  {:user => user.id, :expires_at => 5.minutes.from_now}
end

def user_with_perms(perms)
  perms = perms.collect{|p| Permission.find_by_name(p) || Permission.create(:name => p) }
  perms.each do |p|
    p.resource_type = 'Host' if p.name =~ /discovered_hosts$/
    p.resource_type = 'DiscoveryRule' if p.name =~ /discovery_rules$/
    p.save!
  end
  role = FactoryBot.create :role
  perms.each do |perm|
    FactoryBot.create(:filter, :role => role, :permissions => [perm])
  end
  user = FactoryBot.create :user, :with_mail, :admin => false
  user.roles << role
  user.save
  user
end

def as_default_manager
  as_user(default_manager) do
    yield
  end
end

def as_default_reader
  as_user(default_reader) do
    yield
  end
end

def default_manager
  @default_manager ||= user_with_perms(Foreman::Plugin.find('foreman_discovery').default_roles['Discovery Manager'])
end

def default_reader
  @default_reader ||= user_with_perms(Foreman::Plugin.find('foreman_discovery').default_roles['Discovery Reader'])
end

def set_session_user_default_reader
  set_session_user(default_reader)
end

def set_session_user_default_manager
  set_session_user(default_manager)
end

def extract_form_errors(response)
  response.body.scan(/error-message[^<]*</)
end

def set_default_settings
  Setting['discovery_fact'] = 'discovery_bootif'
  Setting['discovery_hostname'] = 'discovery_bootif'
  Setting['discovery_auto'] = true
  Setting['discovery_reboot'] = true
  Setting['discovery_organization'] = "Organization 1"
  Setting['discovery_location'] = "Location 1"
  Setting['discovery_prefix'] = 'mac'
  Setting['discovery_clean_facts'] = false
  Setting['discovery_lock'] = false
  Setting['discovery_pxelinux_lock_template'] = 'pxelinux_discovery'
  Setting['discovery_pxegrub_lock_template'] = 'pxegrub_discovery'
  Setting['discovery_pxegrub2_lock_template'] = 'pxegrub2_discovery'
  Setting['discovery_always_rebuild_dns'] = true
  Setting['discovery_error_on_existing'] = false
  Setting['discovery_naming'] = 'Fact'
  Setting['discovery_auto_bond'] = false
end

def setup_hostgroup(host)
  domain = FactoryBot.create(:domain)
  subnet = FactoryBot.create(:subnet_ipv4, :network => "192.168.100.0")
  medium = FactoryBot.create(:medium, :organizations => [host.organization], :locations => [host.location])
  os = FactoryBot.create(:operatingsystem, :with_ptables, :with_archs, :media => [medium])
  args = {
    :operatingsystem => os,
    :architecture => os.architectures.first,
    :ptable => os.ptables.first,
    :medium => os.media.first,
    :subnet => subnet,
    :domain => domain,
    :organizations => [host.organization],
    :locations => [host.location]
  }
  if defined?(ForemanPuppet)
    environment = FactoryBot.create(:environment, :organizations => [host.organization], :locations => [host.location])
    args[:environment] = environment
    hostgroup = FactoryBot.create(:hostgroup, :with_rootpass, :with_puppet_enc, **args)
  else
    hostgroup = FactoryBot.create(:hostgroup, :with_rootpass, **args)
  end
  domain.subnets << hostgroup.subnet
  hostgroup.medium.organizations |= [host.organization]
  hostgroup.medium.locations |= [host.location]
  hostgroup.ptable.organizations |= [host.organization]
  hostgroup.ptable.locations |= [host.location]
  hostgroup.domain.organizations |= [host.organization]
  hostgroup.domain.locations |= [host.location]
  hostgroup.subnet.organizations |= [host.organization]
  hostgroup.subnet.locations |= [host.location]
  if defined?(ForemanPuppet)
    hostgroup.environment.organizations |= [host.organization]
    hostgroup.environment.locations |= [host.location]
    hostgroup.puppet_proxy.organizations |= [host.organization]
    hostgroup.puppet_proxy.locations |= [host.location]
    hostgroup.puppet_ca_proxy.organizations |= [host.organization]
    hostgroup.puppet_ca_proxy.locations |= [host.location]
  end
  hostgroup
end

def organization_one
  Organization.find_by_name('Organization 1')
end

def location_one
  Location.find_by_name('Location 1')
end

def current_path_info
  current_url.sub(%r{.*?://}, '')[%r{[/\?\#].*}] || '/'
end

def current_params
  query = current_path_info.split('?')[1]
  Rack::Utils.parse_nested_query query
end

def facts_simple_network100_42
  {
    "interfaces"       => "lo,eth0,eth1",
    "ipaddress"        => "192.168.100.42",
    "ipaddress_eth0"   => "192.168.100.42",
    "ipaddress_eth1"   => "192.168.100.15",
    "macaddress_eth0"  => "AA:BB:CC:DD:EE:FF",
    "macaddress_eth1"  => "AA:BB:CC:DD:EE:F1",
    "discovery_bootif" => "AA:BB:CC:DD:EE:FF",
  }
end

def facts_network_2001_db8
  {
    "interfaces"       => "lo,eth0,eth1",
    "ipaddress6"        => "2001:db8::1",
    "ipaddress6_eth0"   => "2001:db8::1",
    "ipaddress6_eth1"   => "2001:db9::1",
    "macaddress_eth0"  => "AA:BB:CC:DD:EE:FA",
    "macaddress_eth1"  => "AA:BB:CC:DD:EE:FB",
    "discovery_bootif" => "AA:BB:CC:DD:EE:FA",
  }
end

def discover_host_from_facts(facts)
  User.as_anonymous_admin do
    Host::Discovered.import_host(facts)
  end
end

def assert_param(expected, param)
  keys = param.split('.')
  result = current_params
  keys.each do |key|
    result = result[key]
  end
  assert_equal expected, result
end

def assert_selected(select_selector, value)
  select = page.all(select_selector, visible: false).last
  selected = select.find("option[selected='selected']", visible: false) rescue nil
  assert_not_nil selected, "Nothing selected in #{select_selector}"
  assert_equal value.to_s, selected.value
end

def discovered_notification_blueprint
  @blueprint ||= FactoryBot.create(:notification_blueprint,
                                   name: 'new_discovered_host')
end

def failed_discovery_blueprint
  @blueprint ||= FactoryBot.create(:notification_blueprint,
                                   name: 'failed_discovery')
end

def parse_json_fixture(filename, remove_root_element = false)
  raw = JSON.parse(File.read(File.expand_path(File.dirname(__FILE__) + "/facts/#{filename}.json")))
  remove_root_element ? raw['facts'] : raw
end
