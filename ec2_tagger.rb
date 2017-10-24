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

# Instances
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
  end
end

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

# Snapshots
account_id = Aws::STS::Client.new.get_caller_identity.account
filters = { filters: [{
  name: 'owner-id',
  values: [account_id]
}] }

vol_tags = ['Name','Platform','Role','Service']

volume_snaps = []
ec2.volumes.each do |volume|
  next unless volume.snapshot_id
  next if volume.snapshot_id.length == 0
  next if volume_snaps.include?(volume.snapshot_id)
  volume_snaps << volume.snapshot_id
  puts "Copying tags for #{volume.snapshot_id} from #{volume.volume_id}"
  volume.tags.each do |tag|
    next unless vol_tags.include?(tag.key)
    begin
      ec2.snapshot(volume.snapshot_id).create_tags(
        tags: [{
          key: tag.key,
          value: tag.value
        }]
      )
    rescue Aws::EC2::Errors::InvalidSnapshotNotFound
      next
    end
  end
end

untagged_snaps = []
ec2.snapshots(filters).each do |snap|
  next if required_tags.all? do |required_tag|
    snap.tags.any? { |tag| tag.key.eql?(required_tag) }
  end
  untagged_snaps << { id: snap.id, volume_id: snap.volume_id }
end

untagged_snaps.each do |snap|
  begin
    required_tags.each do |required_tag|
      if ec2.volume(snap[:volume_id]).tags.any? { |tag| tag.key.eql?(required_tag) }
        volume_tag = ec2.volume(snap[:volume_id]).tags.select do |tag|
          tag.key.eql?(required_tag)
        end
        # Tag the snapshot with the value obtained from the volume
        puts "Copying Tag:#{required_tag} for snapshot:#{snap[:id]} from #{snap[:volume_id]}"
        ec2.snapshot(snap[:id]).create_tags(
          tags: [{
            key: required_tag,
            value: volume_tag.first.value
          }]
        )
      else
        puts "Tag:#{required_tag} wasn't present on the Volume:#{snap[:volume_id]} for snapshot:#{snap[:id]}"
      end
    end
  rescue Aws::EC2::Errors::InvalidVolumeNotFound
    puts "Volume:#{snap[:volume_id]} no longer exists."
    next
  end
end
