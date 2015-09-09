#!/usr/bin/env ruby

require 'aws-sdk-core'
require 'uri'

def get_running_config
  iam = Aws::IAM::Client.new

  config = {}
  config[:user_detail_list] = []
  config[:group_detail_list] = []
  config[:role_detail_list] = []
  config[:policies] = []

  iam.get_account_authorization_details(max_items: 1000).each do |response|
    config[:user_detail_list] += response[:user_detail_list]
    config[:group_detail_list] += response[:group_detail_list]
    config[:role_detail_list] += response[:role_detail_list]
    config[:policies] += response[:policies]
  end

  config
end

nodes = []
edges = []

config = get_running_config

rroles = config[:role_detail_list]
rroles.each do |role|
  nodes << { id: role[:role_name], group: 'roles', label: role[:role_name] } unless nodes.find{ |n| n[:id] == role[:role_name] }

  role[:role_policy_list].each do |policy|
    document = JSON.parse(URI.decode(policy[:policy_document]))
    nodes << { id: "#{role[:role_name]}#{policy[:policy_name]}", group:'role_policies', label: policy[:policy_name], title: "<pre>#{JSON.pretty_generate(document)}</pre>" } unless nodes.find{ |n| n[:id] == "#{role[:role_name]}#{policy[:policy_name]}" }
    edges << { from: role[:role_name], to: "#{role[:role_name]}#{policy[:policy_name]}" } unless edges.find{ |e| e[:from] == role[:role_name] && e[:to] == "#{role[:role_name]}#{policy[:policy_name]}" }
    [].push(document['Statement']).flatten.each{
      |s|
      resource = s['Resource'].nil? ? s['NotResource'] : s['Resource']
      [].push(resource).flatten.each{
        |r|
        nodes << { id: r, group: 'resources', label: r } unless nodes.find{ |n| n[:id] == r }
        edges << { from:"#{role[:role_name]}#{policy[:policy_name]}", to: r } unless edges.find{ |e| e[:from] == "#{role[:role_name]}#{policy[:policy_name]}" && e[:to] == r }
      }
    }
  end

  running_policies = config[:role_detail_list].find(Proc.new{{attached_managed_policies:[]}}){ |r| r[:role_name] == role[:role_name]}[:attached_managed_policies]

  running_policies.each{
    |p|
    nodes << { id: p[:policy_arn], group: 'policies', label: p[:policy_arn] } unless nodes.find{ |n| n[:id] == p[:policy_arn] }
    edges << { from: role[:role_name], to: p[:policy_arn] } unless edges.find{ |e| e[:from] == role[:role_name] && e[:to] == p[:policy_arn] }
  }
end

File.open('graph.js', 'w') { |file| file.write("var nodes=#{nodes.to_json}; var edges=#{edges.to_json};") }
