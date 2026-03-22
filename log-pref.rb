require 'csv'
require 'json'
require "optparse"
require 'httparty'

ANODYNE_URL = "https://anodyne.wiki/"

options = {
  verbose: false,

  output: nil,
  tmpoutput: nil,
  csv: nil,
  jour: nil,

  start: nil,
  stop: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: log-pref.rb [options]"

  opts.on("-v", "--verbose", "Enable noisy output") do
    options[:verbose] = true
  end

  opts.on("-p PREFERENCES", "--preferences PREFERENCES", "Write to PREFERENCES") do |out|
    options[:output] = out
  end

  opts.on("-l CSV", "--csv FILE", "Plot logs from FILE") do |csv|
    options[:csv] = csv
  end

  opts.on("-j JOURNAL", "--journal JOURNAL", "Plot logs from JOURNAL") do |j|
    options[:jour] = j
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit
  end
end
parser.parse!

if options[:output] == nil
  puts "Preferences file not specified"
  exit 1
end

$lookup_table = {
  "" => nil
}

def encode_symbols(input)
  return input.gsub("α", "%CE%B1").gsub("Α", "%CE%B1").gsub("β", "%CE%B2").gsub("Β", "%CE%B2").gsub("Γ", "%CE%B3").gsub("γ", "%CE%B3").gsub("Δ", "%CE%94").gsub("δ", "%CE%B4").gsub("(", "%28").gsub(")", "%29").gsub("'", "%27")
end

def fetch(url, accept)
  response = HTTParty.get(encode_symbols(url.gsub(" ", "%20")), timeout: 50, headers: { "accept" => accept} )

  return nil if response.code != 200

  return response.body
end

def lookup_sub (name)
  return $lookup_table[name] if $lookup_table.has_key?(name)

  sleep 0.5
  url = ANODYNE_URL + "api/substance/#{name}"
  puts "Lookup: #{url}"

  json_content = fetch(url, "application/json")
  return nil if json_content == nil

  if json_content == '{"NotFound": True}'
    $lookup_table[name] = nil
    return nil 
  end

  json_props = JSON.parse(json_content)
  if json_props == nil or json_props["NotFound"] == true
    $lookup_table[name] = nil
    return nil
  end

  $lookup_table[name] = json_props["Title"]

  return json_props["Title"]
end

tried_titles = []

def load_prefs (prefs_path)
  prefs = File.read(prefs_path)
  return {} if prefs == nil

  prefs_props = JSON.parse(prefs)
  return {} if prefs_props == nil

  return prefs_props
end

DOSE_PATTERN = /\A
  (?<min>\d+(?:\.\d+)?)      # first number
  (?:-(?<max>\d+(?:\.\d+)?))? # optional second number
  (?<unit>[a-zA-Zµ]+)        # unit
\z/x

def parse_measurement(str)
  match = DOSE_PATTERN.match(str)
  return nil unless match

  min  = match[:min].to_f
  max  = match[:max]&.to_f
  unit = match[:unit]

  if max
    { type: :range, min: min, max: max, unit: unit }
  else
    { type: :single, value: min, unit: unit }
  end
end

prefs = load_prefs(options[:output])


logs = nil
csv_data = nil

if options[:csv] != nil and options[:csv] != ""
  logs = CSV.read(options[:csv], headers: true)
  csv_data = logs
  puts "Input: Csv: #{options[:csv]}"
  #logs = File.read(options[:csv])
elsif options[:jour] != nil and options[:jour] != ""
  jdata = JSON.parse(File.read(options[:jour]))
  logs = CSV.generate(headers: true) do |csv|
    csv << ["timestamp","user","med","amount","ROA","comment"]
    jdata["experiences"].each do |experience|
      experience["ingestions"].each do |ingestion|
        csv << [
          Time.at(ingestion["time"] / 1000).utc.strftime("%Y-%m-%dT%H:%M:%S.%3N") + "Z",
          "user",
          ingestion["substanceName"],
          "#{ingestion["dose"]}#{ingestion["units"]}",
          ingestion["administrationRoute"],
          ""
        ]
      end
    end
  end
  csv_data = CSV.parse(logs, headers: true)
  puts "Input: Json: #{options[:jour]}"
else
  exit 1
end
if csv_data == nil
  #puts opts
  exit 1
end

csv_data.sort_by { |log| log['med'] }.each do |log|
  title = lookup_sub(log['med'])
  if title == nil
    puts "Lookup failed: #{log['med']}"
    next
  end
  comments = []
  if log['comment']
    log['comment'].split(' ').each do |comment|
      comments << comment
    end
  end

  if title != nil and !tried_titles.include?(title)
    tried_titles << title
    puts "Adding: #{title}"

    prefs["TriedSubstances"] = Array.new if prefs["TriedSubstances"] == nil

    entry = { Name: title, Routes: [ { Name: log['ROA'].downcase, Dosage: log['amount'] } ] }

    comments.each do |comment|
      if comment.end_with?('-salt')
        entry[:Salts] = [] if entry[:Salts] == nil

        salt = comment.delete_suffix('-salt').downcase
        entry[:Salts] << salt if not entry[:Salts].include?(salt)
      end
    end

    prefs["TriedSubstances"] << entry
  else
    prefs["TriedSubstances"].each do |entry|
      next if entry[:Name] != title

      comments.each do |comment|
        if comment.end_with?('-salt')
          entry[:Salts] = [] if entry[:Salts] == nil

          salt = comment.delete_suffix('-salt').downcase
          entry[:Salts] << salt if not entry[:Salts].include?(salt)
        end
      end

      amount_mg = nil
      if log['amount'].end_with?('mcg')
        amount_mg = log['amount'].delete_suffix('mcg').to_f / 1000.0
      elsif log['amount'].end_with?('mg')
        amount_mg = log['amount'].delete_suffix('mg').to_f
      elsif log['amount'].end_with?('g')
        amount_mg = log['amount'].delete_suffix('g').to_f * 1000.0
      else
        amount_mg = 0.0
      end

      route_set = false
      entry[:Routes].each do |route|
        next if route[:Name] != log['ROA'].downcase

        if route[:Dosage] == nil
          route[:Dosage] = "#{amount_mg.round(1).to_s.sub(/\.0$/, '')}mg"
        elsif amount_mg != nil and amount_mg != 0.0
          old = parse_measurement(route[:Dosage])

          if old != nil and old[:unit] != nil
            case old[:unit]
            when "g"
              old[:value] * 1000.0 if old[:value] != nil
              old[:min] * 1000.0 if old[:min] != nil
              old[:max] * 1000.0 if old[:max] != nil
            when "mcg"
              old[:value] / 1000.0 if old[:value] != nil
              old[:min] / 1000.0 if old[:min] != nil
              old[:max] / 1000.0 if old[:max] != nil
            end

            case old[:type]
            when :single
              if old[:value] < amount_mg.round(1)
                route[:Dosage] = "#{old[:value].round(1).to_s.sub(/\.0$/, '')}-#{amount_mg.round(1).to_s.sub(/\.0$/, '')}mg"
                puts "Adjusting dosage: #{route[:Name]}: #{route[:Dosage]}"
              elsif old[:value] > amount_mg.round(1)
                route[:Dosage] = "#{amount_mg.round(1).to_s.sub(/\.0$/, '')}-#{old[:value].round(1).to_s.sub(/\.0$/, '')}mg"
                puts "Adjusting dosage: #{route[:Name]}: #{route[:Dosage]}"
              end
            when :range
              if old[:max] < amount_mg.round(1)
                route[:Dosage] = "#{old[:min].round(1).to_s.sub(/\.0$/, '')}-#{amount_mg.round(1).to_s.sub(/\.0$/, '')}mg"
                puts "Adjusting dosage: #{route[:Name]}: #{route[:Dosage]}"
              elsif old[:min] > amount_mg.round(1)
                route[:Dosage] = "#{amount_mg.round(1).to_s.sub(/\.0$/, '')}-#{old[:max].round(1).to_s.sub(/\.0$/, '')}mg"
                puts "Adjusting dosage: #{route[:Name]}: #{route[:Dosage]}"
              end
            end
          end
        end
        route_set = true
      end

      if !route_set and amount_mg != nil
        puts "Route added: #{log['ROA'].downcase}"
        route = { Name: log['ROA'].downcase }
        route[:Dosage] = "#{amount_mg.round(1).to_s.sub(/\.0$/, '')}mg"
        entry[:Routes] << route
      end
    end
  end
end

prefs_text = JSON.pretty_generate(prefs)
File.write(options[:output], prefs_text)
