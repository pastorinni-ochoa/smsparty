module Phone
  class User
    attr_accessor :name, :role, :real_name, :phone_number, :receives_messages
    def initialize
      @receives_messages = true
    end

    def self.all
      redis.keys.map do |name|
        create_from_hash(redis.mapped_hmget(name, :name, :phone_number, :role, :receives_messages))
      end
    end

    def receives_messages
      if @receives_messages == 'true' || @receives_messages == true
        true
      else
        false
      end
    end

    def self.find_by_name(name)
      hash = redis.mapped_hmget(name, :phone_number, :name, :role, :real_name, :receives_messages)
      create_from_hash(hash)
    end

    def self.find_by_phone_number(number)
      all.detect do |user|
        user.phone_number == number
      end
    end

    def redis
      redis ||= Phone::Redis.new
    end

    def delete
      redis.remove_user(name)
    end

    def self.redis
      redis ||= Phone::Redis.new
    end

    def self.create_from_hash(hash)
      new.tap do |user|
        hash.each do |key, value|
          value = nil if value == ''
          value = false if value == 'false'
          value = true if value == 'true'
          user.instance_variable_set(key.to_s.prepend('@'), value)
        end
      end
    end
    def boolean_receiveing_text(string_of_bool)
      string_of_bool == 'true' || string_of_bool == 'True'
    end

    def attributes_to_hash
      {
        name: name,
        role: role,
        phone_number: phone_number,
        receives_messages: receives_messages ,
        real_name: real_name
      }
    end

    def save
      redis.save_user(self)
    end
  end
end
