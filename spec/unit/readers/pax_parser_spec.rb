# frozen_string_literal: true

RSpec.describe MiniTarball::PaxParser do
  describe ".parse" do
    it "parses a single record" do
      # Format: "length key=value\n"
      # "12 path=foo\n" => length 12
      data = "12 path=foo\n"
      result = described_class.parse(data)

      expect(result).to eq({ "path" => "foo" })
    end

    it "parses multiple records" do
      data = "12 path=foo\n13 uname=bar\n"
      result = described_class.parse(data)

      expect(result).to eq({ "path" => "foo", "uname" => "bar" })
    end

    it "handles values with equals signs" do
      # key=a=b=c => length is 13 (2 digits + space + key=a=b=c + newline = 2+1+9+1=13)
      data = "13 key=a=b=c\n"
      result = described_class.parse(data)

      expect(result).to eq({ "key" => "a=b=c" })
    end

    it "handles empty values" do
      # "7 key=\n" is 7 bytes total
      data = "7 key=\n"
      result = described_class.parse(data)

      expect(result).to eq({ "key" => "" })
    end

    it "handles UTF-8 values" do
      # "20 path=文件.txt\n" - length includes the 12 byte path (3 chars * 3 bytes + 4)
      path = "文件.txt"
      record = " path=#{path}\n"
      length = record.bytesize + 2 # +2 for the length digits
      data = "#{length}#{record}"
      result = described_class.parse(data)

      expect(result).to eq({ "path" => path })
    end

    it "handles long paths" do
      long_path = "a" * 200
      record = " path=#{long_path}\n"
      length = record.bytesize + 3 # +3 for the length digits (3 digit number)
      data = "#{length}#{record}"
      result = described_class.parse(data)

      expect(result).to eq({ "path" => long_path })
    end

    it "parses mtime with nanosecond precision" do
      mtime = "1613419894.123456789"
      record = " mtime=#{mtime}\n"
      length = record.bytesize + 2
      data = "#{length}#{record}"
      result = described_class.parse(data)

      expect(result).to eq({ "mtime" => mtime })
    end

    it "parses common pax attributes" do
      # Build a typical pax extended header
      records = []
      attributes = {
        "path" => "/very/long/path/to/file.txt",
        "linkpath" => "/link/target",
        "uid" => "1000",
        "gid" => "1000",
        "uname" => "testuser",
        "gname" => "testgroup",
        "size" => "1234567890",
        "mtime" => "1613419894.123",
      }

      data = +""
      attributes.each do |key, value|
        record = " #{key}=#{value}\n"
        length = record.bytesize + record.bytesize.to_s.length
        data << "#{length}#{record}"
      end

      result = described_class.parse(data)

      attributes.each { |key, value| expect(result[key]).to eq(value) }
    end

    describe "error handling" do
      it "raises InvalidHeaderError for missing space" do
        data = "12path=foo\n"

        expect { described_class.parse(data) }.to raise_error(
          MiniTarball::InvalidHeaderError,
          /missing space/,
        )
      end

      it "raises InvalidHeaderError for missing equals" do
        data = "10 pathfoo\n"

        expect { described_class.parse(data) }.to raise_error(
          MiniTarball::InvalidHeaderError,
          /missing equals/,
        )
      end

      it "raises InvalidHeaderError for invalid length" do
        data = "abc path=foo\n"

        expect { described_class.parse(data) }.to raise_error(MiniTarball::InvalidHeaderError)
      end

      it "raises InvalidHeaderError for truncated record" do
        data = "99 path=foo\n"

        expect { described_class.parse(data) }.to raise_error(
          MiniTarball::InvalidHeaderError,
          /Truncated/,
        )
      end
    end
  end
end
