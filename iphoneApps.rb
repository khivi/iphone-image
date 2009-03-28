#!/usr/bin/ruby -w


# sudo port install imagemagick
# sudo gem install rubyzip
# sudo gem install libxml-ruby
# sudo gem install rmagick

require 'rubygems'
gem 'libxml-ruby', '>= 1.1.3'
gem 'rubyzip', '>= 0.9.1'

require 'pathname'
require 'zip/zipfilesystem'
require 'net/http'
require 'xml'
require 'sqlite3'
require 'optparse'

$plutil="/usr/bin/plutil"
$mobileAppDir=Pathname.new(ENV['HOME'])+"Music/iTunes/Mobile Applications"

class AppDB
    @@db="appdb"
    @@database=nil
    def self.create
        self.close
        File.delete @@db  rescue nil
        @@database=SQLite3::Database.open(@@db)
        ## APP
        @@database.execute("CREATE TABLE IF NOT EXISTS APPS (APPID INTEGER NOT NULL, APPNAME CHAR NOT NULL, COMPANY CHAR NOT NULL, GENRE CHAR NOT NULL, ICON BLOB NOT NULL);")
        @@database.execute("CREATE UNIQUE INDEX IF NOT EXISTS APPID_INDEX ON APPS (APPID);")
        @@database.execute("CREATE INDEX IF NOT EXISTS GENRE_INDEX ON APPS (GENRE);")
        ## IMAGE
        @@database.execute("CREATE TABLE IF NOT EXISTS IMAGE_POSITION (APPID INTEGER NOT NULL, X INTEGER NOT NULL, Y CHAR NOT NULL);")
        @@database.execute("CREATE UNIQUE INDEX IF NOT EXISTS IMAGE_APPID_INDEX ON IMAGE_POSITION (APPID);")
    end

    def self.open
        if (@@database == nil)
            @@database=SQLite3::Database.open(@@db)
        end
    end

    def self.insert_position(id,x,y)
        begin
             @@database.execute("INSERT OR REPLACE INTO IMAGE_POSITION VALUES (?,?,?)",id,x,y)
        rescue  SQLite3::SQLException => ex
            raise "#{id} #{ex.message}"
        end
    end

    def self.count
        @@database.get_first_value("SELECT COUNT(*) FROM APPS") 
    end

    def self.icon(appid)
        @@database.get_first_value("SELECT ICON FROM APPS WHERE APPID = :appid",:appid => appid)
    end

    def self.name(appid)
        @@database.get_first_value("SELECT APPNAME FROM APPS WHERE APPID = :appid",:appid => appid)
    end

    def self.position(appid)
        @@database.get_first_row("SELECT X,Y FROM IMAGE_POSITION WHERE APPID = :appid",:appid => appid)
    end

    def self.appids
        appids = []
        @@database.execute("SELECT APPID FROM APPS") do |row|
            appids << row[0]
        end
        appids
    end

    def self.insert_app(id,name,company,genre,icon)
        begin
             @@database.execute("INSERT OR REPLACE INTO APPS VALUES (?,?,?,?,?)",id,name,company,genre,SQLite3::Blob.new(icon))
        rescue  SQLite3::SQLException => ex
            puts "ERR:#{id}"
            puts "#{ex.message}"
            exit
        end
    end

    def self.close
        if (@@database != nil)
            if (not @@database.closed?)
                  @@database.close
            end
            @@database = nil
        end
    end
end

class AppList
    def self.get_value_for_key(doc,key,type)
        doc.find_first("/plist/dict/key[text()='#{key}']/following-sibling::#{type}").content
    end
    def self.getApps
        puts "Get Applications..."
        AppDB.create
        Pathname.glob($mobileAppDir+"*.ipa").each do |appIpa|
            tmpfile=Tempfile.new("iphoneApps")
            tmpfile.write(Zip::ZipFile.open(appIpa).read("iTunesMetadata.plist"))
            tmpfile.flush
            IO.popen("#{$plutil} -convert xml1 -o - #{tmpfile.path}") do |plist|
                doc = XML::Document.io(plist)
                #price=get_value_for_key(doc,"priceDisplay",:string)
                appId=get_value_for_key(doc,"itemId",:integer)
                appName=get_value_for_key(doc,"playlistName",:string)
                company=get_value_for_key(doc,"playlistArtistName",:string)
                genre=get_value_for_key(doc,"genre",:string)
                iconUrl=get_value_for_key(doc,"softwareIcon57x57URL",:string)
                icon = Net::HTTP.get(URI.parse(iconUrl))
                AppDB.insert_app(appId,appName,company,genre,icon)
                puts "#{appId}|#{appName}|#{company}|#{genre}"
            end
            tmpfile.close()
        end
        AppDB.close
     end
end

class ImageParams
    @@max=604
    @@icon=57
    @@border=3
    def self.calculate
        puts "Image Calculation..."
        AppDB.open
        count=AppDB.count.to_i
        if (Math.sqrt(count) * @@icon > @@max)
            raise "Number of application #{count} cannot fit in image"
        end
        appids=AppDB.appids
        x = @@border+@@icon/2
        y = @@border+@@icon/2
        AppDB.count.to_i.times do |i|
            AppDB.insert_position(appids[i],x,y)
            x += @@icon+@@border
            if ((x +@@icon/2+@border) > @@max)
                x = @@icon/2
                y += @@icon+@@border
            end
        end
        AppDB.close
    end
end

class GenerateImage
    def self.generate
        puts "GenerateImage...."
        AppDB.open
        appids=AppDB.appids
        appids.each do |appid|
            icon=AppDB.icon(appid)
            label=AppDB.name(appid)
            puts "label=#{label} appid=#{appid}"
        end
        AppDB.close
    end
end

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-l","--list-apps","Obtain list of applications") do |v|
        options[:list]=v
    end
    opts.on("-c","--calculate-image","Calculate image parameters ") do |v|
        options[:calculate]=v
    end
    opts.on("-g","--gen-image","Generate image ") do |v|
        options[:image]=v
    end
end.parse!

if (options[:list])
    AppList.getApps
end
if (options[:calculate])
    ImageParams.calculate
end
if (options[:image])
    GenerateImage.generate
end
