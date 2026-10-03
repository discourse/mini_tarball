# frozen_string_literal: true

require_relative "spec_helper"

# These scenarios assert GNU-specific reader policies and command-line options.
RSpec.describe "GNU tar Autotest reader behavior", :gnu_tar_autotest do
  include_context "with a GNU tar Autotest workspace"
  let(:tar_binary) { GnuTar.binary_path }

  describe "owner.at", gnu_tar_source: "owner.at" do
    it "lists explicit owner names and numeric IDs independently" do
      write_archive do |tar|
        tar.file "file",
                 content: "",
                 uid: 1234,
                 gid: 5678,
                 uname: "Archive Owner",
                 gname: "Archive Group's Team",
                 mtime: Time.at(0),
                 mode: 0o644
      end
      expect(run_tar("-tvf", archive_path)).to match(
        %r{\A-rw-r--r-- Archive Owner/Archive Group's Team\s+0 1970-01-01 00:00 file\n\z},
      )
      expect(run_tar("--numeric-owner", "-tvf", archive_path)).to match(
        %r{\A-rw-r--r-- 1234/5678\s+0 1970-01-01 00:00 file\n\z},
      )
    end
  end

  describe "numeric.at", gnu_tar_source: "numeric.at" do
    [0, 2**21 - 1, 2**21, 123_456_789].each do |id|
      it "lists numeric owner #{id} when both name fields are empty" do
        write_archive do |tar|
          tar.directory "dir", uid: id, gid: id, uname: "", gname: ""
          tar.file "dir/file", content: "", uid: id, gid: id, uname: "", gname: ""
        end
        listing = run_tar("-tvf", archive_path)
        expect(listing.lines.size).to eq(2)
        expect(listing.lines.map { |line| line.split[1] }).to eq(["#{id}/#{id}"] * 2)
        expect(run_tar("--numeric-owner", "-tvf", archive_path)).to eq(listing)
      end
    end
  end

  describe "time01.at", gnu_tar_source: "time01.at" do
    # GNU-format adaptation: nonnegative whole seconds only, including the
    # octal/base-256 boundary. The upstream fractional/negative PAX matrix is excluded.
    [0, 1, 2**31 - 1, 2**31, 2**32 - 1, 2**32, 2**33 - 1, 2**33, 253_402_300_799].each do |seconds|
      it "lists timestamp #{seconds} without truncation" do
        timestamp = Time.at(seconds).utc
        write_archive { |tar| tar.file "file", content: "", mtime: timestamp }
        listing = run_tar("--full-time", "-tvf", archive_path)
        expect(listing).to include(timestamp.strftime("%Y-%m-%d %H:%M:%S"))
      end
    end
  end

  describe "extrac06.at", gnu_tar_source: "extrac06.at" do
    it "applies the extraction umask to directory modes on repeated extraction" do
      write_archive { |tar| tar.directory "dir", mode: 0o777 }
      FileUtils.mkdir_p(extracted("dir"), mode: 0o755)
      2.times do
        # The shell sets the umask, because JRuby and TruffleRuby don't support
        # the umask option of Process.spawn.
        _out, err, status =
          Open3.capture3(
            { "TAR_OPTIONS" => nil },
            "sh",
            "-c",
            "umask 022 && exec \"$0\" \"$@\"",
            tar_binary,
            "-xf",
            archive_path,
            "-C",
            extract_dir,
            "--no-same-permissions",
          )
        expect(status.success?).to be(true), err
        expect(extracted("dir")).to have_mode(0o755)
      end
    end
  end

  describe "extrac21.at", gnu_tar_source: "extrac21.at" do
    it "delays directory permissions when a symlink follows a sibling directory" do
      write_archive do |tar|
        tar.directory "a"
        tar.directory "a/readonly", mode: 0o555
        tar.file "a/readonly/file", content: "file"
        tar.directory "a/sibling"
        tar.symlink "a/readonly/link", target: "../sibling/target", allow_parent_references: true
        tar.file "a/sibling/target", content: "target"
      end
      extract_archive("--delay-directory-restore")
      expect(extracted("a/readonly")).to have_mode(0o555)
      expect(extracted("a/readonly/file")).to be_file(content: "file")
      expect(File.binread(extracted("a/readonly/link"))).to eq("target")
    end
  end

  describe "incr02.at", gnu_tar_source: "incr02.at" do
    it "preserves directory timestamps with directory-first member ordering" do
      timestamp = Time.utc(2001, 2, 3, 4, 5, 6)
      write_archive do |tar|
        tar.directory "dir", mtime: timestamp
        tar.directory "dir/first", mtime: timestamp
        tar.directory "dir/second", mtime: timestamp
        tar.file "dir/first/file", content: "content", mtime: timestamp
      end
      extract_archive("--delay-directory-restore")
      %w[dir dir/first dir/second dir/first/file].each do |name|
        expect(File.mtime(extracted(name))).to eq(timestamp)
      end
    end
  end

  describe "verify.at and difflink.at", gnu_tar_source: %w[verify.at difflink.at] do
    it "compares emitted file metadata and links against disk and detects a replaced hardlink" do
      FileUtils.mkdir_p(File.join(work_dir, "source"))
      source = File.join(work_dir, "source/file")
      File.binwrite(source, "content")
      write_archive do |tar|
        tar.file "file", from: source
        tar.symlink "symlink", target: "file", mtime: File.mtime(source)
        tar.hardlink "hardlink", target: "file", mtime: File.mtime(source)
      end
      extract_archive
      expect(run_tar("--compare", "-f", archive_path, "-C", extract_dir)).to eq("")
      File.unlink(extracted("hardlink"))
      File.symlink("file", extracted("hardlink"))
      expect(run_tar("--compare", "-f", archive_path, "-C", extract_dir, status: 1)).to include(
        "hardlink: Not linked to file",
      )
    end
  end
  describe "link01.at", gnu_tar_source: "link01.at" do
    it "keeps content when a repeated filename is encoded as a hardlink to itself" do
      write_archive do |tar|
        tar.file "nested/file", content: "original"
        tar.hardlink "nested/file", target: "nested/file"
      end
      extract_archive
      expect(extracted("nested/file")).to be_file(content: "original")
    end
  end

  describe "extrac12.at", gnu_tar_source: "extrac12.at" do
    it "restores children before applying read-only permissions to dot" do
      write_archive do |tar|
        tar.directory ".", mode: 0o555
        tar.file "./first", content: "first"
        tar.file "second", content: "second"
      end
      extract_archive
      expect(extract_dir).to have_mode(0o555)
      expect(extracted("first")).to be_file(content: "first")
      expect(extracted("second")).to be_file(content: "second")
    end
  end
end
