require_relative 'currency'
require_relative 'settings'
require 'pry'
require 'minitest/autorun'
require 'rest-client'
require 'mocha/mini_test'


class TestCurrencylayerWrapper < Minitest::Test

    def setup
        # this is really an integration test and should probably be
        # separate, otherwise it'll start to get annoying
        @currency = CurrencylayerWrapper.new(CURRENCYLAYER_TOKEN)
    end

    def test_raises_error
        currency = CurrencylayerWrapper.new('oeuhoeuntoheu')

        assert_raises CurrencyLayerError do
           currency.historical_rates(Date.new(2017, 1, 1), ['eur'])
        end
    end

    def test_historical_rate
        result = @currency.historical_rate(Date.new(2017, 1, 1), ['eur'])
        assert_equal('2017-01-01', result['date'])
        assert_equal(1, result['quotes'].length)
    end

    def test_historical_rate_today
        result = @currency.historical_rate(Date.today, ['eur'])
        assert_equal(Date.today.strftime('%Y-%m-%d'), result['date'])
        assert_equal(1, result['quotes'].length)
    end

    def test_real_time_rates
        result = @currency.real_time_rates(['eur'])
        assert_equal(1, result['quotes'].length)
    end
end


class CurrencyCalculatorTest < Minitest::Test

    def setup
        @currency_calc = CurrencyCalculator.new('onuethoeu')
        @currency_calc.currencylayer = mock()

        @historical = {
            "success"=>true,
            "terms"=>"https://currencylayer.com/terms",
            "privacy"=>"https://currencylayer.com/privacy",
            "historical"=>true,
            "date"=>"2017-01-01",
            "timestamp"=>1483315199,
            "source"=>"USD",
            "quotes"=>{"USDEUR"=>0.949104, "USDSEK" => 8.9131}
        }
    end

    def test_exchange_rate_works_usd
        @currency_calc.currencylayer.expects('historical_rate')
            .returns(@historical)
            .with(Date.new(2017, 1, 1), ['eur', 'sek', 'usd'])
        result = @currency_calc.exchange_rates('usd', ['eur', 'sek'], Date.new(2017, 1, 1))

        assert_equal(0.9491, result['USDEUR'])
        assert_equal(8.9131, result['USDSEK'])
    end

    def test_currency_exchange
        @currency_calc.currencylayer.expects('historical_rate')
            .returns(@historical)
            .with(Date.today, ['sek', 'eur'])

        result = @currency_calc.currency_exchange('eur', ['sek'], 10)
        assert_equal(93.9107, result['EURSEK'])
    end

    def test_currency_exchange_with_usd
        @currency_calc.currencylayer.expects('historical_rate')
            .returns(@historical)
            .with(Date.today, ['eur', 'sek', 'usd'], )

        result = @currency_calc.currency_exchange('usd', ['eur', 'sek'], 10)
        assert_equal(9.491, result['USDEUR'])
    end

    def test_currency_exchange_with_date
        @currency_calc.currencylayer.expects('historical_rate')
            .returns(@historical)
            .with(Date.new(2017, 1, 1), ['sek', 'eur'])

        result = @currency_calc.currency_exchange('eur',
                                                  ['sek'],
                                                  10,
                                                  Date.new(2017, 1, 1))
        assert_equal(93.9107, result['EURSEK'])
    end

    def test_exchange_rate
        @currency_calc.currencylayer.expects('historical_rate')
            .returns(@historical)
            .with(Date.new(2017, 1, 1), ['sek', 'eur'])

        result = @currency_calc.exchange_rates('eur', ['sek'], Date.new(2017, 1, 1))
        assert_equal(9.3911, result['EURSEK'])
        assert_equal(1, result['EUREUR'])
        assert_equal(2, result.length)
    end

    def test_highest_rate
        for x in (1..5)
            historical = Marshal.load(Marshal.dump(@historical))
            historical['date'] = "2017-01-#{x}"
            historical['quotes']['USDSEK'] = 8.9131 + x
            @currency_calc.currencylayer.expects('historical_rate')
                .returns(historical)
                .with(Date.new(2017, 1, x), ['sek', 'eur'])
        end

        dates = (1..5).map{|d| Date.new(2017, 1, d)}
        result = @currency_calc.highest_rate('eur', 'sek', dates)

        assert_equal(result['date'], Date.new(2017, 1, 5))
    end
end


class SocialMediaTest < MiniTest::Test
    def setup
        @sm = SocialMedia.new
        @sm.twitter_client = mock()
        @sm.twilio_client = mock()
    end

    def test_twitter_method
        @sm.twitter_client.expects('update')
        @sm.twitter('test')
    end

    def test_twilio_method
        @sm.twilio_client.expects('messages')
        assert_raises NoMethodError do
            @sm.twilio('test')
        end
    end
end
