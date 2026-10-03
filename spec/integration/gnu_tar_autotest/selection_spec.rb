# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "GNU tar Autotest selective extraction", :gnu_tar_autotest do
  include_context "with a GNU tar Autotest workspace"
  let(:tar_binary) { GnuTar.binary_path }

  describe "extrac04.at", gnu_tar_source: "extrac04.at" do
    it "matches excludes against stored member paths" do
      write_archive do |tar|
        tar.file "./top1", content: "top"
        tar.directory "dir"
        tar.directory "dir/sub"
        %w[dir/one dir/two dir/sub/one dir/sub/two].each { |name| tar.file name, content: name }
      end
      listing =
        run_tar("-tf", archive_path, "--exclude=./*1", "--exclude=d*/one", "--exclude=d*/s*/two")
      expect(listing.lines.map(&:chomp)).to eq(%w[dir/ dir/sub/ dir/two])
    end
  end

  describe "extrac05.at", gnu_tar_source: "extrac05.at" do
    it "skips intervening members with different padding when selecting files" do
      sizes = [118, 223, 517, 110]
      write_archive do |tar|
        sizes.each_with_index { |size, index| tar.file "file#{index}", content: index.to_s * size }
      end
      extract_archive("file0", "file3")
      expect(Dir.children(extract_dir).sort).to eq(%w[file0 file3])
      expect(extracted("file0")).to be_file(content: "0" * 118)
      expect(extracted("file3")).to be_file(content: "3" * 110)
    end
  end

  describe "extrac10.at", gnu_tar_source: "extrac10.at" do
    it "extracts selected members into separate destinations" do
      FileUtils.mkdir_p(extracted("other"))
      write_archive do |tar|
        tar.directory "dir"
        tar.file "dir/file", content: "in directory"
        tar.file "file", content: "other destination"
      end
      run_tar("-xf", archive_path, "-C", extract_dir, "dir", "-C", "other", "file")
      expect(extracted("dir/file")).to be_file(content: "in directory")
      expect(extracted("other/file")).to be_file(content: "other destination")
    end
  end

  describe "extrac17.at", gnu_tar_source: "extrac17.at" do
    it "selects a subtree before stripping its path components" do
      write_archive do |tar|
        tar.directory "dir"
        tar.directory "dir/first"
        tar.directory "dir/second"
        tar.file "dir/first/one", content: "selected"
        tar.file "dir/second/two", content: "excluded"
      end
      extract_archive("--strip-components=2", "dir/first/")
      expect(Dir.children(extract_dir)).to eq(["one"])
      expect(extracted("one")).to be_file(content: "selected")
    end
  end

  describe "extrac18.at", gnu_tar_source: "extrac18.at" do
    it "reports an existing file but still extracts later members with keep-old-files" do
      File.binwrite(extracted("first"), "keep")
      write_archive do |tar|
        tar.file "first", content: "replace"
        tar.file "second", content: "new"
      end
      run_tar("-xf", archive_path, "-C", extract_dir, "--keep-old-files", status: 2)
      expect(extracted("first")).to be_file(content: "keep")
      expect(extracted("second")).to be_file(content: "new")
    end
  end

  describe "extrac20.at", gnu_tar_source: "extrac20.at" do
    [false, true].each do |keep_symlink|
      it "#{keep_symlink ? "keeps" : "replaces"} an existing directory symlink" do
        FileUtils.mkdir_p(extracted("target"))
        File.symlink("target", extracted("dir"))
        write_archive do |tar|
          tar.directory "dir"
          tar.file "dir/file", content: "content"
        end
        options = keep_symlink ? ["--keep-directory-symlink"] : []
        extract_archive(*options)
        expect(File.symlink?(extracted("dir"))).to eq(keep_symlink)
        expect(extracted("dir/file")).to be_file(content: "content")
        expect(File.exist?(extracted("target/file"))).to eq(keep_symlink)
      end
    end
  end

  describe "extrac23.at", gnu_tar_source: "extrac23.at" do
    it "keeps existing directory metadata when requested" do
      FileUtils.mkdir_p(extracted("dir"))
      File.chmod(0700, extracted("dir"))
      write_archive do |tar|
        tar.directory "dir", mode: 0o755
        tar.file "dir/file", content: "content"
      end
      extract_archive("--no-overwrite-dir")
      expect(extracted("dir")).to have_mode(0o700)
      expect(extracted("dir/file")).to be_file(content: "content")
    end
  end

  describe "extrac25.at", gnu_tar_source: "extrac25.at" do
    it "reports a dangling parent symlink and still extracts the following member" do
      File.symlink("missing", extracted("dir"))
      write_archive do |tar|
        tar.file "dir/file", content: "cannot extract"
        tar.file "after", content: "still extracted"
      end
      run_tar("-xf", archive_path, "-C", extract_dir, status: 2)
      expect(extracted("dir")).to be_symlink(target: "missing")
      expect(File.exist?(extracted("missing"))).to be false
      expect(extracted("after")).to be_file(content: "still extracted")
    end
  end
end
