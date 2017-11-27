secrets = YAML.load_file('./secrets.yml')
ACCOUNT_SID=secrets.fetch('account_sid')
AUTH_TOKEN=secrets.fetch('auth_token')
PHONE_NUMBER=secrets.fetch('phone_number')

Phonelib.default_country = "US"

class Party < Sinatra::Base
  attr_reader :users, :redis
  def client
    @client ||= Twilio::REST::Client.new(ACCOUNT_SID, AUTH_TOKEN)
  end

  def redis
    @redis ||= Phone::Redis.new(url: 'redis://localhost:6379')
  end

  set :public_folder => "public", :static => true

  post '/' do
    do_the_right_thing(params)
  end

  get "/" do
    erb :welcome
  end

  def do_the_right_thing(message_params)
    if message_params.fetch('Body').match(/^\~/)
      process_command(message_params)
    else
      message_all_others(message_params)
    end
  end

  def process_command(message_params)
    catch :command_error do
      command = message_params.fetch('Body').match(/\~(?<command>\w+) *(?<name>.*)/)[:command]
      case command
      when "add"
        add_user(message_params)
      when "stop"
        stop_user_receiving(message_params)
      when "start"
        start_user_receiving(message_params)
      when "help"
        show_help(message_params)
      when "remove"
        remove_user(message_params)
      when 'list'
        list_users(message_params)
      when 'name'
        change_name(message_params)
      end
    end
  rescue => e
    puts e
    binding.pry
  end

  def change_name(message_params)
    user = message_params.fetch('From')
    command, name  = disect_command_and_name(message_params)
    user.name = name
    user.save
    send_message message_params.fetch('From'), 'success'
  end

  def list_users(message_params)
    phone_number = Phonelib.parse(message_params.fetch('From')).to_s
    body = ''
    Phone::User.all.each do |user|
      body << "#{user.name} - #{Phonelib.parse(user.phone_number).national}\n"
    end
    send_message(phone_number, body)
  end

  def show_help(message_params)
    phone_number = Phonelib.parse(message_params.fetch('From')).to_s
    body = <<-EOF.gsub(/^ */, '')
      ~help display this message
      ~stop stop messages from flowing
      ~start start messages flowing
      ~name change your name
      ~list list users
    EOF
    send_message(phone_number, body)
  rescue => e
    puts e
    binding.pry
  end

  def start_user_receiving(message_params)
    command, name  = disect_command_and_name(message_params)
    if name
      user = Phone::User.find_by_name(name)
    else
      phone_number = message_params.fetch('From')
      user = Phone::User.find_by_phone_number(phone_number)
    end
    user.receives_messages = true
  rescue => e
    puts e
    binding.pry
  end

  def stop_user_receiving(message_params)
    command, name  = disect_command_and_name(message_params)
    if name
      user = Phone::User.find_by_name(name)
    else
      phone_number = message_params.fetch('From')
      user = Phone::User.find_by_phone_number(phone_number)
    end
    user.receives_messages = false
    user.save
  end

  def message_sender

  end

  def message_all_others(message_params)
    users = Phone::User.all.select do |user|
      user.receives_messages == true #&& Phonelib.parse(user.phone_number).to_s != message_params.fetch('From')
    end
    from_number = Phonelib.parse(message_params.fetch('From'))
    from_user = Phone::User.find_by_phone_number(from_number.to_s)
    message = message_params.fetch('Body').prepend("#{from_user.name}: ")
    media = get_media(message_params)
    users.each do |user|
      Thread.new do
        send_message(user.phone_number, message, media)
      end
    end
  rescue => e
    binding.pry
  end

  def get_media(message_params)
    message_params.select do |key, value|
      key =~ /^MediaUrl\d/
    end.values
  end


  def send_message(phone_number, body, media)
    if media.size == 0
      sms_send(phone_number, body)
    else
      mms_send(phone_number, body, media)
    end
  end

  def mms_send(phone_number, body, media_url)
    if ENV['RACK_ENV'] != 'test'
      client.account.messages.create(
        from: PHONE_NUMBER,
        to: phone_number,
        body: body,
        media_url: media_url
      )
    end
  end

  def sms_send(phone_number, body)
    if ENV['RACK_ENV'] != 'test'
      client.account.messages.create(
        from: PHONE_NUMBER,
        to: phone_number,
        body: body
      )
    end
  end

  def message_all

  end

  def add_user(message_params)
    command, name, phone_number  = disect_message(message_params)
    u = Phone::User.new
    u.name = name
    u.phone_number = phone_number
    u.save
  rescue => e
    puts e
    binding.pry
  end

  def remove_user(message_params)
    command, name  = disect_command_and_name(message_params)
    user = Phone::User.find_by_name(name)
    user.delete
  end

  def users
    @users = Phone::User.all
  end

  def name_from_message_params(message_params)
  end

  def disect_command_and_name(message_params)
    match = message_params.fetch('Body').match(/^\~(?<command>\w+)$/)
    return [match[:command], nil] if match
    match = message_params.fetch('Body').match(/\~(?<command>\w+) *(?<name>.+)/)
    command = match[:command]
    name    = match[:name]
    [command, name]
  end

  def disect_message(message_params)
    match = message_params.fetch('Body').match(/\~(?<command>\w+) +(?<name>\w+):(?<number>.+)/)
    command = match[:command]
    name    = match[:name]
    number  = match[:number]
    number_validator = Phonelib.parse(number)
    if number_validator.valid?
      number = number_validator.to_s
      [command , name , number ]
    else
      throw :command_error
    end
  rescue => e
    puts e
    binding.pry
  end
end

unless ENV['RACK_ENV'] == 'test'
  [
    ['Doug🌹', '+14155044070'],
    # ['James',  '+15094387804'],
    # ['Erich🎖', '+12067132457'],
    # ['Pat🏅',   '+15108539653'],
    # ['SteveD', '+119099691023'],
    # ['SteveB🐷', '+12069419587'],
    # ['PatrickG🇵', '+16022846085'],
    # ['Gideon', '+15098331698'],
    # # ['Party Don', ''],
    # ['Mollie', '+12066695369'],
    # # ['Jessica',''],
    # ['Khayah', '+13606899568'],
    # ['Jenn', '+12069725366'],
    # ['Ray', '+14258026471'],
    # ['Lance', '+12069627778'],
    # ['BroQueen', '+17202772456']
  ].each do |name_phone|
    user = Phone::User.new
    user.name = name_phone[0]
    user.phone_number = name_phone[1]
    user.save
  end
end
