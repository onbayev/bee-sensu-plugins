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
    def get_server_runtime_info(hostname,servername)
	command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
                        {"core-service":"platform-mbean"},
                        {"type":"runtime"}],
                    "include-runtime":"true",
                    "json.pretty":1}'
	result = get_jboss_metrics(command)
	return result["result"]
    end	
    def get_server_public_interface(hostname,servername)
        command = '{"operation":"read-resource",
                    "address":[
                        {"host":"'+hostname+'"},
                        {"server":"'+servername+'"},
                        {"interface":"public"}],
                    "include-runtime":"true",
                    "json.pretty":1}'
        result = get_jboss_metrics(command)
        return result["result"]["resolved-address"]
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
			pid = get_server_runtime_info(host.to_s,server.to_s)["name"].split("@")[0]
			interface = get_server_public_interface(host.to_s,server.to_s)
		        metrics=`jstat -gcutil -t rmi://#{pid}@#{interface}:1099|tail -n 1`.split(" ")
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","S0"].join("."),metrics[1].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","S1"].join("."),metrics[2].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","E"].join("."),metrics[3].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","O"].join("."),metrics[4].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","P"].join("."),metrics[5].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","YGC"].join("."),metrics[6].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","YGCT"].join("."),metrics[7].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","FGC"].join("."),metrics[8].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","FGCT"].join("."),metrics[9].to_s.gsub(',', '.').to_f, timestamp
                        output ["stats","xjboss",host.to_s,server.to_s,"jstat","GCT"].join("."),metrics[10].to_s.gsub(',', '.').to_f, timestamp

		    end		
		end
		end
		end
	end	
    ok
   end
end
