#!/usr/bin/env ruby

require 'ruby-graphviz'
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

g = GraphViz::new( "structs", "type" => "graph" )
g[:rankdir] = "LR"
#g[:splines] = "ortho"

config = get_running_config

rroles = config[:role_detail_list]
rroles.each do |role|
  g.add_node(role[:role_name])

  role[:role_policy_list].each do |policy|
    g.add_node("#{role[:role_name]}#{policy[:policy_name]}", {label: policy[:policy_name]})
    g.add_edges(role[:role_name],"#{role[:role_name]}#{policy[:policy_name]}")

    document = JSON.parse(URI.decode(policy[:policy_document]))
    [].push(document['Statement']).flatten.each{
      |s|
      resource = s['Resource'].nil? ? s['NotResource'] : s['Resource']
      [].push(resource).flatten.each{
        |r|
        g.add_node(r)
        g.add_edges("#{role[:role_name]}#{policy[:policy_name]}",r, {label: s['Action'].to_s })
      }
    }
  end

  running_policies = config[:role_detail_list].find(Proc.new{{attached_managed_policies:[]}}){ |r| r[:role_name] == role[:role_name]}[:attached_managed_policies]

  running_policies.each{
    |p|
    g.add_node(p[:policy_arn])
    g.add_edges(role[:role_name], p[:policy_arn])
  }
end


g.output(dot: 'graph.dot')

