#!/usr/bin/ruby -w


# Run as root
#  gem install rubyzip
#  gem install libxml-ruby

require 'rubygems'
gem 'libxml-ruby', '>= 1.1.3'
gem 'rubyzip', '>= 0.9.1'

require 'pathname'
require 'zip/zipfilesystem'
require 'xml'

plutil="/usr/bin/plutil"

mobileAppDir=Pathname.new(ENV['HOME'])+"Music/iTunes/Mobile Applications"

def get_value_for_key(doc,key,type)
    doc.find_first("/plist/dict/key[text()='#{key}']/following-sibling::#{type}").content
end


Pathname.glob(mobileAppDir+"*.ipa").each do |appIpa|
    tmpfile=Tempfile.new("iphoneApps")
    tmpfile.write(Zip::ZipFile.open(appIpa).read("iTunesMetadata.plist"))
    tmpfile.flush
    IO.popen("#{plutil} -convert xml1 -o - #{tmpfile.path}") do |plist|
        doc = XML::Document.io(plist)
        #price=get_value_for_key(doc,"priceDisplay",:string)
        appName=get_value_for_key(doc,"playlistName",:string)
        company=get_value_for_key(doc,"playlistArtistName",:string)
        appId=get_value_for_key(doc,"itemId",:integer)
        genre=get_value_for_key(doc,"genre",:string)
        iconUrl=get_value_for_key(doc,"softwareIcon57x57URL",:string)
        puts "#{appId}|#{appName}|#{company}|#{genre}"
    end
    tmpfile.close()
end

