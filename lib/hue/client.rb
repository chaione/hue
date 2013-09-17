require 'net/http'
require 'multi_json'
require 'upnp/ssdp' rescue puts "You need to add this to your Gemfile:  \n\ngem 'upnp', :git => 'https://github.com/turboladen/upnp.git'"

module Hue
  class Client
    attr_reader :username

    def initialize(username = '1234567890')
      unless USERNAME_RANGE.include?(username.length)
        raise InvalidUsername, "Usernames must be between #{USERNAME_RANGE.first} and #{USERNAME_RANGE.last}."
      end

      @username = username
      validate_user
    end

    def bridge
      # Pick the first one for now. In theory, they should all do the same thing.
      bridge = bridges.first
      raise NoBridgeFound unless bridge
      bridge
    end

    def bridges
      @bridges ||= begin
        bs = []
        upnp_json = MultiJson.load(upnp_response)
        upnp_json.each do |hash|
          bridge = Bridge.new(self, hash)
          bridge.ip = load_ip_from_sspd if bridge.ip.nil?
          raise "Can't find bridge ip address from UPnP or SSDP" if bridge.ip.nil?
          bs << bridge
        end
        bs
      end
    end

    def lights
      @lights ||= begin
        ls = []
        json = MultiJson.load(Net::HTTP.get(URI.parse("http://#{bridge.ip}/api/#{@username}")))
        json['lights'].each do |key, value|
          ls << Light.new(self, bridge, key, value)
        end
        ls
      end
    end

    def add_lights
      uri = URI.parse("http://#{bridge.ip}/api/#{@username}/lights")
      http = Net::HTTP.new(uri.host)
      response = http.request_post(uri.path, nil)
      MultiJson.load(response.body).first
    end

    def light(id)
      self.lights.select { |l| l.id == id }.first
    end

  private

    def load_ip_from_sspd
      devices = UPnP::SSDP.search 'uuid:2f402f80-da50-11e1-9b23-0017880a6912'
      if devices.any?
        return devices.first[:location][/((\d+)\.){3}(\d+)/]
      end
      nil
    end

    def upnp_response
      Net::HTTP.get(URI.parse('http://www.meethue.com/api/nupnp'))
    end

    def validate_user
      response = MultiJson.load(Net::HTTP.get(URI.parse("http://#{bridge.ip}/api/#{@username}")))

      if response.is_a? Array
        response = response.first
      end

      if error = response['error']
        parse_error(error)
      end
      response['success']
    end

    def register_user
      body = {
        devicetype: 'Ruby',
        username: @username
      }

      uri = URI.parse("http://#{bridge.ip}/api")
      http = Net::HTTP.new(uri.host)
      response = MultiJson.load(http.request_post(uri.path, MultiJson.dump(body)).body).first

      if error = response['error']
        parse_error(error)
      end
      response['success']
    end

    def parse_error(error)
      # Find error or return
      klass = Hue::ERROR_MAP[error['type']]
      klass = UnknownError unless klass

      # Raise error
      raise klass.new(error['description'])
    rescue  Hue::UnauthorizedUser
      register_user
    end
  end
end
