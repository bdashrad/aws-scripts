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
account_id = Aws::STS::Client.new.get_caller_identity.account
filters = { filters: [{
  name: 'owner-id',
  values: [account_id]
}] }

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
