# frozen_string_literal: true

if ENV['CC_TEST_REPORTER_ID']
  require 'simplecov'
  SimpleCov.start
end

require 'image_optim/pack'
require 'image_optim/path'

ENV['PATH'] = [
  ImageOptim::Pack.path,
  ENV['PATH'],
].compact.join File::PATH_SEPARATOR

RSpec.configure do |c|
  c.before do
    stub_const('ImageOptim::Config::GLOBAL_PATH', ImageOptim::Path::NULL)
    stub_const('ImageOptim::Config::LOCAL_PATH', ImageOptim::Path::NULL)
    ImageOptim.class_eval{ def pack; end }
  end

  c.order = :random
end

IMAGEMAGICK_PREFIX = ImageOptim::Cmd.capture('which magick').empty? ? [] : %w[magick]

def flatten_animation(image)
  if image.image_format == :gif
    flattened = image.temp_path
    command = (IMAGEMAGICK_PREFIX + %W[
      convert
      #{image}
      -coalesce
      -append
      #{flattened}
    ]).shelljoin
    expect(ImageOptim::Cmd.run(command)).to be_truthy
    flattened
  else
    image
  end
end

def mepp(image_a, image_b)
  coalesce_a = flatten_animation(image_a)
  coalesce_b = flatten_animation(image_b)
  output = ImageOptim::Cmd.capture((IMAGEMAGICK_PREFIX + %W[
    compare
    -metric MEPP
    -alpha Background
    #{coalesce_a.to_s.shellescape}
    #{coalesce_b.to_s.shellescape}
    #{ImageOptim::Path::NULL}
    2>&1
  ]).join(' '))
  unless [0, 1].include?($CHILD_STATUS.exitstatus)
    fail "compare #{image_a} with #{image_b} failed with `#{output}`"
  end

  num_r = '\d+(?:\.\d+(?:[eE][-+]?\d+)?)?'
  output[/\((#{num_r}), #{num_r}\)/, 1].to_f
end

RSpec::Matchers.define :be_smaller_than do |expected|
  match{ |actual| actual.size < expected.size }
end

RSpec::Matchers.define :be_similar_to do |expected, max_difference|
  match do |actual|
    @diff = mepp(actual, expected)
    @diff <= max_difference
  end
  failure_message do |actual|
    "expected #{actual} to have at most #{max_difference} difference from "\
      "#{expected}, got mean error per pixel of #{@diff}"
  end
end

SkipConditions = Hash.new do |cache, name|
  cache[name] = case name
  when :any_file_mode_allowed
    Tempfile.open('posix') do |f|
      File.chmod(0, f.path)
      'full file modes are not support' unless (File.stat(f.path).mode & 0o777).zero?
    end
  when :inodes_support
    'inodes are not supported' if File.stat(__FILE__).ino.zero?
  when :signals_support
    begin
      Process.kill(0, 0)
      nil
    rescue
      'signals are not supported'
    end
  else
    fail "Unknown check #{name}"
  end
end
