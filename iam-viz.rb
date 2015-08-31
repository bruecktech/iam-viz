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

config = get_running_config

rroles = config[:role_detail_list]
rroles.each do |role|
  g.add_node(role[:role_name])

  role[:role_policy_list].each do |policy|
    g.add_node(policy[:policy_name])
    g.add_edges(role[:role_name],policy[:policy_name])

    document = JSON.parse(URI.decode(policy[:policy_document]))
    puts document
  end

#  iam.list_attached_role_policies(role_name: role[:role_name])[:attached_policies].each do |policy|
#    g.add_node(policy[:policy_arn])
#    g.add_edges(role[:role_name],policy[:policy_arn])
#
#  end
end


g.output(dot: 'graph.dot')

