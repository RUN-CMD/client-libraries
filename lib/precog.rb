# Copyright (C) 2011 by ReportGrid, Inc. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# No portion of this Software shall be used in any application which does not
# use the Precog platform to provide some subset of its functionality.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

require 'logger'
require 'net/http'
require 'pp'
require 'time'
require 'uri'

require 'rubygems'
require 'json'


module Precog
  #log          = Logger.new(STDOUT)

  # API server constants
  module API
    HOST = 'api.precog.io'
    PORT = 80
    PATH = 'v1'
  end

  # Path constants
  module Paths
    TOKENS = '/auth/tokens'
    VFS    = '/vfs/'
  end

  class Token 
    attr_reader :path_permissions, :query_permissions, :grants, :expiration

    class << self
      def readwrite(path) 
        Token.new(
          [PathPermissions.new(path, PathPermissions::READ), PathPermissions.new(path, PathPermissions::WRITE)],
          [QueryPermissions.new(path)]
        )
      end

      def readonly(path) 
        Token.new(
          [PathPermissions.new(path, PathPermissions::READ)],
          [QueryPermissions.new(path)]
        )
      end
    end

    def initialize(path_permissions = [], query_permissions = [], grants = [], expiration = nil)
      @permissions = {}
      @permissions[:path] = path_permissions unless path_permissions.nil? || path_permissions.empty?
      @permissions[:data] = query_permissions unless query_permissions.nil? || query_permissions.empty?
      @grants = grants || []
      @expiration = expiration
    end
    
    def to_json(*a)
      {
        'permissions' => @permissions,
        'grants' => @grants,
        'expired' => !@expiration.nil? && @expiration < Time.now
      }.to_json(*a)
    end
  end

  class PathPermissions
    READ = 'PATH_READ'
    WRITE = 'PATH_WRITE'

    attr_reader :path, :access_type

    def initialize(path, access_type) 
      @path = path
      @access_type = access_type
    end

    def to_json(*a)
      {
        'pathSpec' => { 'subtree' => @path },
        'pathAccess' => @access_type,
        'mayShare' => true
      }.to_json(*a)
    end
  end

  class QueryPermissions
    attr_reader :path, :owner

    def initialize(path, owner = "[HOLDER]")
      @path = path
      @owner = owner
    end

    def to_json(*a)
      {
        'pathSpec' => { 'subtree' => @path },
        'ownershipSpec' => { 'ownerRestriction' => @owner },
        'dataAccess' => 'DATA_QUERY',
        'mayShare' => true
      }.to_json(*a)
    end
  end

  # Base exception for all Precog errors
  class PrecogError < StandardError
    def intialize(message)
      #log.error(message)
      super
    end
  end

  # Raised on HTTP response errors
  class HttpResponseError < PrecogError
    attr_reader :code
    def initialize(message, code)
      super(message)
      @code = code
    end
  end

  # Simple HTTP client for Precog API
  class HttpClient

    # Initialize an HTTP connection
    def initialize(token_id, host, port, path_prefix)
      @token_id    = token_id
      @host        = host
      @port        = port
      @path_prefix = path_prefix || 'v1'
      @conn        = Net::HTTP.new(host, port)
    end

    # Send an HTTP request
    def method_missing(name, path, options={})
      options[:body]    ||= ''
      options[:headers] ||= {}
      options[:parameters] ||= {}

      # Add token id to path and set headers
      path = "#{@path_prefix}#{path}?tokenId=#{@token_id}"
      options[:parameters].each do |k, v|
        path += "&#{k}=#{v}"
      end

      options[:headers].merge!({'Content-Type' => 'application/json'})

      # Set up message
      message = "#{name.to_s.upcase} to #{@host}:#{@port}#{path} with headers (#{options[:headers].to_json })"
      if options[:body]
        body = options[:body].to_json
        message += " and body (#{body})"
      end

      # Send request and get response
      begin
        request = Net::HTTP.const_get(name.to_s.capitalize).new(path)
        options[:headers].each { |k,v| request.add_field(k, v) }
        response = @conn.request(request, body)
      rescue StandardError => e
        message += " failed (#{e})"
        raise HttpResponseError.new(message, 500)
      end

      # Check HTTP status code
      if response.code.to_i != 200
        message += " returned non-200 status (#{response.code}): #{response.inspect}"
        raise HttpResponseError.new(message, response.code.to_i)
      end

      # Try parsing JSON response
      begin
        response_data = JSON.parse(response.body)
      rescue StandardError => e
        response_data = response.body
        if response_data.start_with?('"') && response_data.end_with?('"')
          response_data = response_data[1...-1]
        end
      end

      message += " returned: #{response_data}"

      response_data
    end
  end

  # Precog base class
  class Precog

    # Initialize an API client
    def initialize(token_id, host = API::HOST, port = API::PORT, service_path = API::PATH)
      @api = HttpClient.new(token_id, host, port, service_path)
    end

    # Create a new token
    def new_token(token)
      puts(token.to_json)
      @api.post("#{Paths::TOKENS}", :body => token)
    end

    # Return information about a token
    def token
      @api.get("#{Paths::TOKENS}")
    end

    # Delete a token
    def delete_token(token_id)
      @api.delete("#{Paths::TOKENS}", :parameters => { :delete => token_id })
    end

    # Store a record at the specified path
    def store(path, record)
      # Sanitize path
      path = "#{Paths::VFS}/#{path}" unless path.start_with?(Paths::VFS)
      path = sanitize_path(path)

      @api.post(path, :body => record)
    end

    # Send a quirrel query to be evaluated relative to the specified base path.
    def query(path, query)
      path = "#{Paths::VFS}/#{path}" unless path.start_with?(Paths::VFS)
      path = sanitize_path(path)

      @api.get(path, :parameters => { :q => query })
    end

    # Explore the specified path to determine its children
    def list_children(path)
      path = "#{Paths::VFS}/#{path}" unless path.start_with?(Paths::VFS)
      path = sanitize_path(path)

      @api.get(path)
    end

    private

    # Sanitize a URL path
    def sanitize_path(path)
      newpath = path.gsub(/\/+/, '/')
      while newpath.gsub!(%r{([^/]+)/\.\./?}) { |match|
        $1 == '..' ? match : ''
      } do end
      newpath.gsub(%r{/\./}, '/').sub(%r{/\.\z}, '/')
    end

    # Properties must always be prefixed with a period
    def sanitize_property(property)
      if property && !property.start_with?('.')
        property = ".#{property}"
      end
      property
    end
  end
end
