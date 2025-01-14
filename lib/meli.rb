# encoding: UTF-8

require 'rubygems'
require 'net/http'
require 'net/https'
require 'json'
require 'uri'
require 'constants'

class Meli
  attr_accessor :access_token, :refresh_token
  attr_reader :secret, :app_id, :https, :open_timeout, :read_timeout

  #constructor
  def initialize(app_id = nil, secret = nil, access_token = nil,
                 refresh_token = nil, open_timeout: nil, read_timeout: nil)
    @access_token = access_token
    @refresh_token = refresh_token
    @app_id = app_id
    @secret = secret
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    api_url = URI.parse API_ROOT_URL
    @https = Net::HTTP.new(api_url.host, api_url.port)
    @https.use_ssl = true
    @https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    @https.ssl_version = :TLSv1
    @https.open_timeout = open_timeout
    @https.read_timeout = read_timeout
  end

  def self.auth_url_country(iso_country_code)
    const_get "AUTH_URL_#{iso_country_code}"
  end

  #AUTH METHODS
  def auth_url(redirect_URI, iso_country_code = "BR")
    params = {:client_id  => @app_id, :response_type => 'code', :redirect_uri => redirect_URI}
    url = "#{Meli.auth_url_country(iso_country_code)}?#{to_url_params(params)}"
  end

  def authorize(code, redirect_URI)
    params = { :grant_type => 'authorization_code', :client_id => @app_id, :client_secret => @secret, :code => code, :redirect_uri => redirect_URI}

    uri = make_path(OAUTH_URL, params)

    req = Net::HTTP::Post.new(uri.path)
    req['Accept'] = 'application/json'
    req['User-Agent'] = SDK_VERSION
    req['Content-Type'] = "application/x-www-form-urlencoded"
    req.set_form_data(params)
    response = @https.request(req)

    case response
    when Net::HTTPSuccess
      response_info = JSON.parse response.body
      #convert hash keys to symbol
      response_info = Hash[response_info.map{ |k, v| [k.to_sym, v] }]

      @access_token = response_info[:access_token]
      if response_info.has_key?(:refresh_token)
        @refresh_token = response_info[:refresh_token]
      else
        @refresh_token = '' # offline_access not set up
      end
      @access_token
    else
      # response code isn't a 200; raise an exception
      response.error!
    end

  end

  def get_refresh_token()
    if !@refresh_token.nil? and !@refresh_token.empty?
      params = {:grant_type => 'refresh_token', :client_id => @app_id, :client_secret => @secret, :refresh_token => @refresh_token}

      uri = make_path(OAUTH_URL, params)

      req = Net::HTTP::Post.new(uri.path)
      req['Accept'] = 'application/json'
      req['User-Agent'] = SDK_VERSION
      req['Content-Type'] = "application/x-www-form-urlencoded"
      req.set_form_data(params)
      response = @https.request(req)

      case response
      when Net::HTTPSuccess
        response_info = JSON.parse response.body

        #convert hash keys to symbol
        response_info = Hash[response_info.map{ |k, v| [k.to_sym, v] }]

        @access_token = response_info[:access_token]
        @refresh_token = response_info[:refresh_token]
      else
        # response code isn't a 200; raise an exception
        response.error!
      end
    else
      raise "Offline-Access is not allowed."
    end
  end


  #REQUEST METHODS
  def execute(req, options = {})
    req['Accept'] = 'application/json'
    req['User-Agent'] = SDK_VERSION
    req['Content-Type'] = 'application/json'
    @https.open_timeout = options[:open_timeout] || open_timeout
    @https.read_timeout = options[:read_timeout] || read_timeout

    @https.request(req)
  ensure
    @https.open_timeout = open_timeout
    @https.read_timeout = read_timeout
  end

  def get(path, params = {}, options = {})
    uri = make_path(path, params)
    req = Net::HTTP::Get.new("#{uri.path}?#{uri.query}")
    execute req, options
  end

  def post(path, body, params = {}, options = {})
    uri = make_path(path, params)
    req = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
    req.set_form_data(params)
    req.body = body.to_json unless body.nil?
    execute req, options
  end

  def put(path, body, params = {}, options = {})
    uri = make_path(path, params)
    req = Net::HTTP::Put.new("#{uri.path}?#{uri.query}")
    req.set_form_data(params)
    req.body = body.to_json unless body.nil?
    execute req, options
  end

  def delete(path, params = {}, options = {})
    uri = make_path(path, params)
    req = Net::HTTP::Delete.new("#{uri.path}?#{uri.query}")
    execute req, options
  end

  def options(path, params = {}, options = {})
    uri = make_path(path, params)
    req = Net::HTTP::Options.new("#{uri.path}?#{uri.query}")
    execute req, options
  end

  def open_timeout=(open_timeout)
    @open_timeout = open_timeout
    @https.open_timeout = open_timeout
  end

  def read_timeout=(read_timeout)
    @read_timeout = read_timeout
    @https.read_timeout = read_timeout
  end

private
  def to_url_params(params)
    URI.escape(params.collect{|k,v| "#{k}=#{v}"}.join('&'))
  end

  def make_path(path, params = {})
    # Making Path and add a leading / if not exist
    unless path =~ /^http/
      path = "/#{path}" unless path =~ /^\//
      path = "#{API_ROOT_URL}#{path}"
    end
    path = "#{path}?#{to_url_params(params)}" if params.keys.size > 0
    uri = URI.parse path
  end


end  #class
