#!/usr/bin/env ruby

require 'aws-sdk'

required_tags = %w[
  Environment
  Name
  Platform
  Role
  Service
  terraform
]

applications = {
  cloveretl: { Platform: 'ots', Role: 'back-end', Service: 'edi' },
  consul: { Platform: 'ots', Role: 'config', Service: 'infrastructure', Environment: 'shared-infra' },
  crwriter: { Platform: 'php', Role: 'back-end', Service: 'reporting' },
  eno: { Platform: 'ots', Role: 'database', Service: 'edi' },
  'eno-bastion': { Platform: 'ots', Role: 'database', Service: 'edi' },
  'legacy-titan': { Platform: 'php', Role: 'back-end', Service: 'core' },
  legacy_titan: { Platform: 'php', Role: 'back-end', Service: 'core' },
  mongo: { Platform: 'ots', Role: 'database', Service: 'core' },
  rama: { Platform: 'python', Role: 'back-end', Service: 'edi' },
  recoverx: { Platform: 'ots', Role: 'backup', Service: 'infrastructure', Environment: 'shared-infra' },
  'reporting-api': { Platform: 'php', Role: 'back-end', Service: 'reporting' },
  shiva: { Platform: 'python', Role: 'back-end', Service: 'core' },
  themis: { Platform: 'php', Role: 'back-end', Service: 'core' },
  transformr: { Platform: 'php', Role: 'back-end', Service: 'reporting' },
  vault: { Platform: 'ots', Role: 'config', Service: 'infrastructure', Environment: 'shared-infra' }
}

ec2 = Aws::EC2::Resource.new

# network interfaces
ec2.network_interfaces.each do |interface|
  begin
    ec2.vpc(interface.vpc_id).tags.each do |tag|
      next unless tag.key.eql?('Environment')
      puts "Getting 'Environment' tag from #{interface.vpc_id} for #{interface.id}."
      interface.create_tags(
        tags: [{
          key: 'Environment',
          value: tag.value
        }]
      )
    end
    next if interface.attachment.nil?
    if interface.attachment.instance_owner_id.eql?('amazon-elb')
      interface.create_tags(
        tags: [{
          key: 'Name',
          value: interface.description
        }]
      )
      match = interface.description.match(/ELB (qa|staging|prod)?-?(\S+)/)
      environment, app = match.captures
      if applications.keys.map { |key| key.to_s }.include?(app)
        environment ||= applications[app.to_sym][:Environment]
        puts "Copying tags for #{interface.id} from #{interface.description}"
        interface.create_tags(
          tags: [
            { key: 'Environment', value: environment },
            { key: 'Platform', value: applications[app.to_sym][:Platform] },
            { key: 'Role', value: applications[app.to_sym][:Role] },
            { key: 'Service', value: applications[app.to_sym][:Service] },
            { key: 'terraform', value: 'true' }
          ]
        )
      end
    end
    next if interface.attachment.instance_id.nil?
    puts "Copying tags for #{interface.id} from #{interface.attachment.instance_id}."
    required_tags.each do |required_tag|
      if ec2.instance(interface.attachment.instance_id).tags.any? { |tag| tag.key.eql?(required_tag) }
        instance_tag = ec2.instance(interface.attachment.instance_id).tags.select do |tag|
          tag.key.eql?(required_tag)
        end
        # Tag the volume with the value obtained from the instance
        interface.create_tags(
          tags: [{
            key: required_tag,
            value: instance_tag.first.value
          }]
        )
      end
    end
  rescue
    next
  end
end
