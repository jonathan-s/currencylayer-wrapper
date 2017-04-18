require 'JSON'
require 'date'

require 'rest-client'
require 'pry'
require 'thor'
require 'twitter'
require 'twilio-ruby'

require_relative 'settings'

class CurrencyLayerError < RestClient::RequestFailed
    def initialize(response, initial_response_code=nil, message=nil)
        @response = response
        @message = message
        @initial_response_code = initial_response_code
    end
end

class CurrencylayerWrapper
    def initialize(token)
        @token = token
    end

    def request(method, endpoint, params={})
        url = "http://apilayer.net/api#{endpoint}"
        params['access_key'] = @token
        resp = RestClient::Request.execute(method: method,
                                           url: url,
                                           headers: {'params' => params})

        body = JSON.load(resp.body)
        if resp.code >= 400 or body['success'] == false
            raise CurrencyLayerError.new(resp, message=body['error']['info'])
        end
        return body
    end

    def real_time_rates(currencies)
        request(:get, '/live', {'currencies' => currencies.join(',')})
    end

    def historical_rate(date, currencies)
        date_str = date.strftime('%Y-%m-%d')
        params = {'date'=> date_str, 'currencies' => currencies.join(',')}
        request(:get, '/historical', params)
    end
end



class CurrencyCalculator
    attr_accessor :currencylayer

    def initialize(token)
        @currencylayer = CurrencylayerWrapper.new(token)
    end

    def currency_exchange(source, targets, amount, date=Date.today)
        """
        Return the Value of a given base currency into one
        or multiple target currencies.
        """
        currencies = targets.push(source)
        result = @currencylayer.historical_rate(date, currencies)

        exchange_money = {}
        source_to_usd = source_to_usd(source, result)
        for currency, usd_to_target in result['quotes']
            source_target = source.upcase + currency[-3..-1]
            exchange_money[source_target] = (source_to_usd * amount * usd_to_target).round(4)
        end
        exchange_money
    end

    def exchange_rates(source, targets, date=Date.today)
        """
        Return the exchange rate(s) of a given base currency into one or more
        target currencies.
        """
        currencies = targets.push(source)
        result = @currencylayer.historical_rate(date, currencies)

        exchange_rates = {}
        source_to_usd = source_to_usd(source, result)

        for currency, usd_to_target in result['quotes']
            conversion_rate = source_to_usd * usd_to_target
            source_target = source.upcase + currency[-3..-1]
            exchange_rates[source_target] = conversion_rate.round(4)
        end
        exchange_rates
    end

    def highest_rate(source, target, dates)
        """
        Return the best exchange rate (highest) and the corresponding date
        in the argument dates.
        """
        highest_rate = 0
        highest_date = nil
        for date in dates
            rates = exchange_rates(source, [target], date)
            source_target = rates[source.upcase + target.upcase]

            if source_target > highest_rate
                highest_rate = source_target
                highest_date = date
            end
        end
        {'date' => highest_date, 'rate' => highest_rate}
    end

    private
    def source_to_usd(source, result)
        if source.upcase == 'USD'
            source_to_usd = 1
        else
            source_to_usd = 1 / result['quotes']["USD#{source.upcase}"]
        end
        source_to_usd
    end
end

class SocialMedia

    attr_accessor :twitter_client
    attr_accessor :twilio_client

    def initialize
        @twitter_client = Twitter::REST::Client.new do |config|
          config.consumer_key        = TWITTER_CONSUMER_KEY
          config.consumer_secret     = TWITTER_CONSUMER_SECRET
          config.access_token        = TWITTER_ACCESS_TOKEN
          config.access_token_secret = TWITTER_ACCESS_SECRET
        end

        @twilio_client = Twilio::REST::Client.new(TWILIO_SID, TWILIO_TOKEN)
    end

    def twitter(msg)
        @twitter_client.update(msg)
    end

    def twilio(msg, to_number=TWILIO_TO_NUMBER)
        @twilio_client.messages.create(
            from: TWILIO_FROM_NUMBER,
            to: to_number,
            body: msg
        )
    end
end


class CurrencyCli < Thor


    def initialize(*args, **kwargs)
        super
        @currency_calc = CurrencyCalculator.new(CURRENCYLAYER_TOKEN)
        @social = SocialMedia.new
        @dt_fmt = '%Y-%m-%d'
        @sub = '/^[\s\t]*|[\s\t]*\n/'
    end

    option :source, :required => true, :aliases => '-s', :banner => 'sek'
    option :targets, :required => true, :aliases => '-t', :banner => 'usd,eur,gbp'
    option :date, :aliases => '-d', :banner => '2017-01-01', :default => Date.today.strftime()
    option :twitter, :default => false, :type => :boolean
    option :sms, :type => :boolean, :default => false
    desc "rates", "Get the exchange rate for a given currency into many target currencies"
    def rates()
        targets = options[:targets].split(',').map{|cur| cur.strip}
        date = Date.strptime(options[:date], @dt_fmt)

        result = @currency_calc.exchange_rates(
            options[:source],
            targets,
            date)

        currency_rates = result.keys.each_with_object({}) {|key, h| h[key[-3..-1]] = result[key]}
        cur_str = currency_rates.map{|k, v| "#{k}: #{v}"}.join('; ')
        msg = <<-EOS.gsub(/^[\s\t]*|[\s\t]*\n/, '').strip()
                    #{options[:source].upcase} have the following exchange rates #{cur_str}
                EOS
        send_to_social_media(options, msg)
    end

    option :source, :required => true, :aliases => '-s', :banner => 'sek'
    option :targets, :required => true, :aliases => '-t', :banner => 'usd,eur,gbp'
    option :amount, :required => true, :aliases => '-a', :banner => '10', :type => :numeric
    option :date, :aliases => '-d', :banner => '2017-01-01', :default => Date.today.strftime()
    option :twitter, :default => false, :type => :boolean
    option :sms, :type => :boolean, :default => false
    desc "exchange", "Exchange a sum of money into many target currencies"
    def exchange()
        targets = options[:targets].split(',').map{|cur| cur.strip}
        date = Date.strptime(options[:date], @dt_fmt)

        result = @currency_calc.currency_exchange(
            options[:source],
            targets,
            options[:amount],
            date)

        currency_rates = result.keys.each_with_object({}) {|key, h| h[key[-3..-1]] = result[key]}
        cur_str = currency_rates.map{|k, v| "#{k}: #{v}"}.join('; ')
        msg = <<-EOS.gsub(/^[\s\t]*|[\s\t]*\n/, '')
                #{options[:amount]} in #{options[:source].upcase} is #{cur_str}
              EOS
        send_to_social_media(options, msg)
    end

    option :source, :required => true, :aliases => '-s', :banner => 'sek'
    option :target, :required => true, :aliases => '-t', :banner => 'eur'
    option :twitter, :default => false, :type => :boolean
    option :sms, :type => :boolean, :default => false
    desc "highest_rate", "Get the highest rate the past 7 days"
    def highest_rate()
        today = Date.today
        seven_days_ago = today - 7
        dates = (0...7).map{|day| seven_days_ago + day}

        result = @currency_calc.highest_rate(
            options[:source],
            options[:target],
            dates)
        msg = <<-EOS.gsub(/^[\s\t]*|[\s\t]*\n/, '')
                #{result['date']} had the highest rate from #{options[:source].upcase}
                to #{options[:target].upcase}: #{result['rate']}
              EOS
        send_to_social_media(options, msg)
    end

    no_commands do
        def send_to_social_media(options, msg)
            puts msg
            if options[:twitter]
                @social.twitter(msg)
            end

            if options[:sms]
                @social.twilio(msg)
            end

            if not options[:sms] and not [:twitter]
                puts "If you want to post to somewhere else use --sms or --twitter"
            end
        end
    end

end


if __FILE__ == $0
    CurrencyCli.start(ARGV)
end
