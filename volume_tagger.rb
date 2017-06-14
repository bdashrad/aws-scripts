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

ec2 = Aws::EC2::Resource.new

# Volumes
untagged_volumes = []
ec2.volumes.each do |volume|
  next unless volume.attachments.any?
  next if required_tags.all? do |required_tag|
    volume.tags.any? { |tag| tag.key.eql?(required_tag) }
  end
  untagged_volumes << { id: volume.volume_id, instance_id: volume.attachments.first.instance_id }
end

untagged_volumes.each do |volume|
  puts "Copying tags for volume:#{volume[:id]} from #{volume[:instance_id]}"
  required_tags.each do |required_tag|
    if ec2.instance(volume[:instance_id]).tags.any? { |tag| tag.key.eql?(required_tag) }
      instance_tag = ec2.instance(volume[:instance_id]).tags.select do |tag|
        tag.key.eql?(required_tag)
      end
      # Tag the volume with the value obtained from the instance
      ec2.volume(volume[:id]).create_tags(
        tags: [{
          key: required_tag,
          value: instance_tag.first.value
        }]
      )
    else
      puts "Tag:#{required_tag} wasn't present on the Instance:#{volume[:instance_id]} for volume:#{volume[:id]}"
    end
  end
end
