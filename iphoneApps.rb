#!/usr/bin/ruby -w

=begin
    iphoneApps.rb - Creates a image of applications installed on our iPhone
    Copyright (C) 2009 Amit Khivesara (iphone@khivi.com)

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

=end

# sudo port install imagemagick
# sudo gem install rubyzip
# sudo gem install libxml-ruby
# sudo gem install rmagick

require 'rubygems'
gem 'libxml-ruby', '>= 1.1.3'
gem 'rubyzip', '>= 0.9.1'
gem 'rmagick', '>= 2.9.1'
gem 'sqlite3-ruby', '>= 1.2.4'

require 'pathname'
require 'optparse'
require 'zip/zipfilesystem'
require 'net/http'
require 'xml'
require 'sqlite3'
require 'RMagick'

$plutil="/usr/bin/plutil"
$mobileAppDir=Pathname.new(ENV['HOME'])+"Music/iTunes/Mobile Applications"

class AppDB
    @@db="appdb"
    @@database=nil
    def self.create
        self.close
        File.delete @@db  rescue nil
        @@database=SQLite3::Database.open(@@db)
        ## APPS
        @@database.execute("CREATE TABLE IF NOT EXISTS APPS (APPID INTEGER NOT NULL, APPNAME CHAR NOT NULL, COMPANY CHAR NOT NULL, GENRE CHAR NOT NULL, ICON BLOB NOT NULL);")
        @@database.execute("CREATE UNIQUE INDEX IF NOT EXISTS APPID_INDEX ON APPS (APPID);")
    end

    def self.open
        if (@@database == nil)
            @@database=SQLite3::Database.open(@@db)
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

    def self.appids
        appids = []
        @@database.execute("SELECT APPID FROM APPS ORDER BY APPNAME COLLATE NOCASE") do |row|
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
            puts appIpa
            Zip::ZipFile.open(appIpa) do |appFile|
                tmpfile=Tempfile.new("iphoneApps")
                tmpfile.write(appFile.read("iTunesMetadata.plist"))
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
        end
        AppDB.close
     end
end


class GenerateImage
    def self.watermark(finalImage)
    mark = Magick::Image.new(finalImage.columns, finalImage.rows) do
        self.background_color = 'none'
        end
    gc = Magick::Draw.new
    gc.annotate(mark, 0, 0, 0, 0, "Image by Khivi") do
        self.gravity = Magick::CenterGravity
        self.pointsize = 64
        self.font_family = "TrueColorMatte"
        self.font_weight = Magick::BoldWeight
        self.font_style = Magick::ObliqueStyle
        self.fill = "grey"
        self.stroke = "none"
        end
    mark
    end

    def self.glass_effect(image)
        glass=Magick::Image.new(image.columns,image.rows) {self.background_color='none'}
        gc=Magick::Draw.new
        gc.fill("rgba(0,0,0,0.45)")
        gc.circle(image.columns/2,-image.rows,image.columns/2,image.rows/2)
        gc.draw(glass)
        image.composite(glass,Magick::CenterGravity, Magick::SoftLightCompositeOp)
    end

    def self.roundedge(image)
        mask=Magick::Image.new(image.columns,image.rows) {self.background_color='black'}
        gc=Magick::Draw.new
        gc.fill('white')
        gc.roundrectangle(0,0,image.columns,image.rows,12,12)
        gc.draw(mask)
        mask.matte=false
        image.matte= true
        image.composite(mask,Magick::CenterGravity, Magick::CopyOpacityCompositeOp)
    end

    def self.generate
        puts "GenerateImage...."
        AppDB.open
        appids=AppDB.appids
        images=Magick::ImageList.new
        appids.each do |appid|
            icon=AppDB.icon(appid)
            label=AppDB.name(appid).slice!(0,13)
            images << self.roundedge(self.glass_effect(Magick::Image.from_blob(icon)[0]))
            images.cur_image['Label']= label
        end
        AppDB.close

        montage=images.montage do 
            self.title = "Applications on my iPhone"
            self.background_color = "black"
            self.geometry = "57x57+15+15"
            self.fill = "white"
            self.pointsize = 10
            self.shadow = true
        end
        raise "Too many images generated"  if montage.length != 1
        montage = montage.watermark(self.watermark(montage), 0.35, 0, Magick::CenterGravity)
        montage.write("apps.png")
    end
end

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-l","--list-apps","Obtain list of applications") do |v|
        options[:list]=v
    end
    opts.on("-g","--gen-image","Generate image ") do |v|
        options[:image]=v
    end
end.parse!

if (options[:list])
    AppList.getApps
end
if (options[:image])
    GenerateImage.generate
end
