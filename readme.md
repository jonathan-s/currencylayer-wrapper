# A simple Currency Calculator

This simple commandline currency calculator post things to social media (if you let it). In `settings.rb` you can make the appropriate settings for your social media accounts. 

Once you are done with your settings you can install all requirements with the following two commands

    gem install bundler
    bundle install

To run the tests for this `currency.rb` run the following command

    ruby tests.rb

To start posting interesting currency related stats to social media you can run the cli with the following. 

    ruby currency.rb --help

The commands that you can do are the following

    ruby currency.rb exchange -s eur -t gbp,sek -a 10
    ruby currency.rb rate -s eur -t gbp,sek
    ruby currency.rb highest_rate -s eur -t gbp

To send a sms add `--sms` or post to twitter with `--twitter`
