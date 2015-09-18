#!/usr/bin/env ruby

require 'aws-sdk-core'
require 'uri'
require 'awesome_print'
require 'yaml'

CONFIG = YAML.load_file('config.yaml')

def parse_arn(arn)
  arn_split = arn.split(':')
  r = {
    service:    arn_split[2] || nil,
    region:     arn_split[3] || nil,
    account_id: arn_split[4] || nil
  }

  if arn_split[6]
    r[:resource_type] = arn_split[5]
    r[:resource] = arn_split[6]
  elsif arn_split[5]
    if arn_split[5].split('/')[1]
      r[:resource_type] = arn_split[5].split('/')[0]
      r[:resource] = arn_split[5].split('/')[1]
    else
      r[:resource_type] = nil
      r[:resource] = arn_split[5]
    end
  else
    r[:resource_type] = nil
    r[:resource] = nil
  end

  r
end

def get_running_config
  roles = CONFIG[:roles]

  config = {}

  roles.each do |role|
    credentials = Aws::AssumeRoleCredentials.new(role_arn: role[:role_arn], role_session_name: 'iam-viz')
    iam = Aws::IAM::Client.new(credentials: credentials)

    account_id = role[:role_arn].split(':')[4].to_sym

    config[account_id] = {
      user_detail_list: [],
      group_detail_list: [],
      role_detail_list: [],
      policies: []
    }

    iam.get_account_authorization_details(max_items: 1000).each do |response|
      config[account_id][:user_detail_list] += response[:user_detail_list]
      config[account_id][:group_detail_list] += response[:group_detail_list]
      config[account_id][:role_detail_list] += response[:role_detail_list]
      config[account_id][:policies] += response[:policies]
    end
  end

  config
end

nodes = []
edges = []

config_all = get_running_config

config_all.each{ |account_id, config|
  rroles = config[:role_detail_list]
  rroles.each do |role|
    nodes << { id: "#{account_id}_#{role[:role_name]}", group: 'roles', label: role[:role_name] } unless nodes.find{ |n| n[:id] == "#{account_id}_#{role[:role_name]}" }

    role[:role_policy_list].each do |policy|
      document = JSON.parse(URI.decode(policy[:policy_document]))
      nodes << { id: "#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}", group:'role_policies', label: policy[:policy_name], title: "<pre>#{JSON.pretty_generate(document)}</pre>" } unless nodes.find{ |n| n[:id] == "#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}" }
      edges << { from: "#{account_id}_#{role[:role_name]}", to: "#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}" } unless edges.find{ |e| e[:from] == "#{account_id}_#{role[:role_name]}" && e[:to] == "#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}" }
      [].push(document['Statement']).flatten.each{
        |s|
        resource = s['Resource'].nil? ? s['NotResource'] : s['Resource']
        [].push(resource).flatten.each{
          |r|
          if parse_arn(r)[:resource_type] == 'role'
            nodes << { id: "#{parse_arn(r)[:account_id]}_#{parse_arn(r)[:resource]}", group: 'roles', label: parse_arn(r)[:resource] } unless nodes.find{ |n| n[:id] == "#{parse_arn(r)[:account_id]}_#{parse_arn(r)[:resource]}" }
            edges << { from:"#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}", to: "#{parse_arn(r)[:account_id]}_#{parse_arn(r)[:resource]}" } unless edges.find{ |e| e[:from] == "#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}" && e[:to] == "#{parse_arn(r)[:account_id]}_#{parse_arn(r)[:resource]}" }
          else
            nodes << { id: r, group: 'resources', label: r } unless nodes.find{ |n| n[:id] == r }
            edges << { from:"#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}", to: r } unless edges.find{ |e| e[:from] == "#{account_id}_#{role[:role_name]}_#{policy[:policy_name]}" && e[:to] == r }
          end
        }
      }
    end

    running_policies = config[:role_detail_list].find(Proc.new{{attached_managed_policies:[]}}){ |r| r[:role_name] == role[:role_name]}[:attached_managed_policies]

    running_policies.each{
      |p|
      nodes << { id: "#{account_id}_#{p[:policy_arn]}", group: 'policies', label: p[:policy_arn] } unless nodes.find{ |n| n[:id] == "#{account_id}_#{p[:policy_arn]}" }
      edges << { from: "#{account_id}_#{role[:role_name]}", to: "#{account_id}_#{p[:policy_arn]}" } unless edges.find{ |e| e[:from] == "#{account_id}_#{role[:role_name]}" && e[:to] == "#{account_id}_#{p[:policy_arn]}" }
    }
  end
}

File.open('graph.js', 'w') { |file| file.write("var nodes=#{nodes.to_json}; var edges=#{edges.to_json};") }
