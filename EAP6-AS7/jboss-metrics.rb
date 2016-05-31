#!/usr/bin/env ruby


require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/metric/cli'
require 'socket'
require 'json'
require 'curb'


class JbossStat < Sensu::Plugin::Metric::CLI::Graphite

  option :scheme,
    :description => "Metric naming scheme, text to prepend to .$parent.$child",
    :long => "--scheme SCHEME",
    :default => "#{Socket.gethostname}.vmstat"
  option :ip,
    :description => "Jboss admin management interface ip address",
    :long => "--ip IP",
    :default => "127.0.0.1"
  option :user,
    :description => "Management user name",
    :long => "--user USER",
    :default => "admin"
  option :password,
    :description => "Management user password",
    :long => "--password PASSWORD",
    :default => "admin"
  option :port,
    :description => "Management port",
    :long => "--port PORT",
    :default => "9990"
  option :datasource,
    :description => "Datasource name",
    :long => "--ds DATASOURCE",
    :default => "DS"
  option :deplaoyment,
    :description => "deplaoyment war",
    :long => "--deplaoyment DEPLOYMENT",
    :default => "test.war"  
	
    def get_jboss_metrics(command)
	result = `curl -s -L --digest http://#{config[:user]}:#{config[:password]}@#{config[:ip]}:#{config[:port]}/management --header "Content-Type: application/json" -d '#{command}'`
	return JSON.parse(result) 
    end
    def get_jboss_global_info()
	command = 
		'{"operation":"read-resource",
		  "recursive-depth":"0",
		  "json.pretty":1}'
	result = get_jboss_metrics(command)		
	return result
    end
    def get_servers(host)
                command = 
                      '{"operation":"read-resource",
                        "address":[{"host":"'+host+'"}],
                        "recursive-depth":0,
                        "json.pretty":1}'
                host_info = get_jboss_metrics(command)
                servers=host_info["result"]["server-config"]
	return servers    
    end
    def get_server_queues(hostname,servername)
	command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
                        {"subsystem":"messaging"},
                        {"hornetq-server":"default"}],
                    "json.pretty":1}'
        result = get_jboss_metrics(command)
        return result["result"]["runtime-queue"]
    end		
    def get_datasource_info(hostname,servername,datasource)
	command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
                        {"subsystem":"datasources"},
                        {"data-source":"'+datasource+'"},
                        {"statistics":"pool"}],
                    "include-runtime":"true",
                    "json.pretty":1}'
	result = get_jboss_metrics(command)
	return result["result"]
    end	
    def get_http_info(hostname,servername)
   	command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
                        {"subsystem":"web"},
                        {"connector":"http"}],
                    "include-runtime":"true",
                    "json.pretty":1}'
        result = get_jboss_metrics(command)
        return result["result"]	
    end			
    def get_web_info(hostname,servername,deployment)
        command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
                        {"deployment":"'+deployment+'"},
                        {"subsystem":"web"}],
                    "include-runtime":"true",
                    "json.pretty":1}'
	result = get_jboss_metrics(command)
        return result["result"]
    end
    def get_messages_info(hostname,servername,queue)
        command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
			{"subsystem":"messaging"},
			{"hornetq-server":"default"},
			{"jms-queue":"'+queue+'"}],
                    "include-runtime":"true",
                    "json.pretty":1}'
        result = get_jboss_metrics(command)
        return result["result"]
    end
    def server_enabled(hostname,servername)
                command =
                      '{"operation":"read-attribute",
			"name":"server-state",
                        "address":[{"host":"'+hostname+'"},
				{"server":"'+servername+'"}],
                        "recursive-depth":0,
                        "json.pretty":1}'
                host_info = get_jboss_metrics(command)
                result=host_info["result"]
	if( result.to_s == "running" )
       		return true
	else
		return false
	end   	
    end				
    def run  
  	timestamp = Time.now.to_i
  	jboss_global_info = get_jboss_global_info()

	hosts = jboss_global_info["result"]["host"]
	hosts.each do |host|  
		if servers = get_servers(host.to_s)
		begin
		servers.each do |server|
		if server_enabled(host.to_s,server.to_s)
			if dsinfo = get_datasource_info(host.to_s,server.to_s,config[:datasource])
			    dsinfo.each do |key,value|
			    	if value.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true	
					output ["stats","jboss",host.to_s,server.to_s,"datasource",key.to_s].join("."),value.to_s, timestamp	
			    	end	
			    end
			end
			if httpinfo = get_http_info(host.to_s,server.to_s)
                            httpinfo.each do |key,value|
                                if value.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true
                                     output ["stats","jboss",host.to_s,server.to_s,"http",key.to_s].join("."),value.to_s, timestamp
                                end
                            end
                        end
			if queues = get_server_queues(host.to_s,server.to_s)
			    queues.each do |queue_name|
			      if webinfo = get_messages_info(host.to_s,server.to_s,queue_name.to_s.split('.')[2].to_s)
                                webinfo.each do |key,value|
                                    if value.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true
                                        output ["stats","jboss",host.to_s,server.to_s,"messages",queue_name.to_s.split('.')[2].to_s,key.to_s].join("."),value.to_s, timestamp
                                    end
                                end
                              end
			    end	
			end
			    if webinfo = get_web_info(host.to_s,server.to_s,config[:deployment])
			    	webinfo.each do |key,value|
                                    if value.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true
                                     	output ["stats","jboss",host.to_s,server.to_s,"web",key.to_s].join("."),value.to_s, timestamp
                                    end
                            	end				
			    end
		    end                        
		end
		end
		end
	end	
    ok
   end
end
