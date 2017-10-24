#!/usr/bin/env ruby

require 'aws-sdk'

ec2 = Aws::EC2::Resource.new

applications = {
  cloveretl: { Platform: 'ots', Role: 'back-end', Service: 'edi' },
  crwriter: { Platform: 'php', Role: 'back-end', Service: 'reporting' },
  'eno-bastion': { Platform: 'ots', Role: 'database', Service: 'edi' },
  legacy_titan: { Platform: 'php', Role: 'back-end', Service: 'core' },
  mongo: { Platform: 'ots', Role: 'database', Service: 'core' },
  rama: { Platform: 'python', Role: 'back-end', Service: 'edi' },
  'reporting-api': { Platform: 'php', Role: 'back-end', Service: 'reporting' },
  shiva: { Platform: 'python', Role: 'back-end', Service: 'core' },
  themis: { Platform: 'php', Role: 'back-end', Service: 'core' },
  transformr: { Platform: 'php', Role: 'back-end', Service: 'reporting' },
}

options = { filters: [{ name: 'tag-key', values: ['Name'] }] }

named_instances = ec2.instances(options)
# instances = []
named_instances.each do |instance|
  instance.tags.each do |tag|
    next unless tag.key.eql?("Name")
    next unless match = tag.value.match(/(qa|staging|prod)-(\S+)/)
    environment, app = match.captures
    next unless applications.keys.map { |key| key.to_s }.include?(app)
    puts "Tagging #{instance.instance_id} (#{tag.value})"
    instance.create_tags(
      tags: [
        { key: 'Environment', value: environment },
        { key: 'Platform', value: applications[app.to_sym][:Platform] },
        { key: 'Role', value: applications[app.to_sym][:Role] },
        { key: 'Service', value: applications[app.to_sym][:Service] },
        { key: 'terraform', value: 'true' }
      ]
    )
    # instances << {
    #   id: instance.instance_id,
    #   name: tag.value,
    #   app: app,
    #   environment: environment,
    #   platform: applications[app.to_sym][:Platform],
    #   role: applications[app.to_sym][:Role],
    #   service: applications[app.to_sym][:Service]
    # }
  end
end
