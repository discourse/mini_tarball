# frozen_string_literal: true

require_relative "spec_helper"

TarExtractor.extractors.each do |extractor|
  RSpec.describe "GNU tar Autotest extraction (#{extractor.name})", :gnu_tar_autotest do
    include_context "with a GNU tar Autotest workspace"
    let(:tar_binary) { extractor.binary_path }

    describe "extrac01.at", gnu_tar_source: "extrac01.at" do
      it "extracts directory entries over existing directories" do
        FileUtils.mkdir_p(extracted("dir"))
        File.binwrite(extracted("dir/keep"), "existing")
        write_archive do |tar|
          tar.directory "dir"
          tar.file "dir/new", content: "new"
        end
        extract_archive
        expect(extracted("dir/keep")).to be_file(content: "existing")
        expect(extracted("dir/new")).to be_file(content: "new")
      end
    end

    describe "extrac02.at", gnu_tar_source: "extrac02.at" do
      it "replaces a regular file with the archived symlink" do
        File.binwrite(extracted("link"), "old")
        write_archive { |tar| tar.symlink "link", target: "target" }
        extract_archive
        expect(extracted("link")).to be_symlink(target: "target")
      end
    end

    describe "extrac07.at", gnu_tar_source: "extrac07.at" do
      it "restores a parent-relative symlink inside a read-only directory" do
        write_archive do |tar|
          tar.file "target", content: "target content"
          tar.directory "readonly", mode: 0o555
          tar.symlink "readonly/link", target: "../target", allow_parent_references: true
        end
        extract_archive
        expect(extracted("readonly")).to have_mode(0o555)
        expect(extracted("readonly/link")).to be_symlink(target: "../target")
        expect(File.binread(extracted("readonly/link"))).to eq("target content")
      end
    end

    describe "extrac08.at", gnu_tar_source: "extrac08.at" do
      it "restores the archived permissions of an existing directory" do
        FileUtils.mkdir_p(extracted("dir"), mode: 0o700)
        write_archive do |tar|
          tar.directory "dir", mode: 0o755
          tar.file "dir/file", content: "content"
        end
        extract_archive("-p")
        expect(extracted("dir")).to have_mode(0o755)
        expect(extracted("dir/file")).to be_file(content: "content")
      end
    end

    describe "extrac13.at", gnu_tar_source: "extrac13.at" do
      it "replaces an existing symlink with a regular member without changing its target" do
        File.binwrite(extracted("target"), "keep me")
        File.symlink("target", extracted("file"))
        write_archive { |tar| tar.file "file", content: "replacement" }
        extract_archive
        expect(File.symlink?(extracted("file"))).to be false
        expect(extracted("file")).to be_file(content: "replacement")
        expect(extracted("target")).to be_file(content: "keep me")
      end
    end

    describe "extrac14.at", gnu_tar_source: "extrac14.at" do
      it "extracts through a symlink naming the destination directory" do
        destination = File.join(work_dir, "destination")
        File.symlink(extract_dir, destination)
        write_archive { |tar| tar.file "file", content: "content" }
        run_tar("-xf", archive_path, "-C", destination)
        expect(extracted("file")).to be_file(content: "content")
      end
    end

    describe "extrac16.at", gnu_tar_source: "extrac16.at" do
      it "restores nested empty directories alongside files" do
        write_archive do |tar|
          tar.directory "parent"
          tar.directory "parent/empty"
          tar.directory "parent/empty/nested"
          tar.file "parent/file", content: "content"
        end
        extract_archive
        expect(extracted("parent/empty/nested")).to be_dir
        expect(Dir.children(extracted("parent/empty/nested"))).to be_empty
        expect(extracted("parent/file")).to be_file(content: "content")
      end
    end

    describe "extrac22.at", gnu_tar_source: "extrac22.at" do
      it "restores children listed before their directory entries" do
        write_archive do |tar|
          tar.symlink "links/link", target: "../files/data", allow_parent_references: true
          tar.directory "links", mode: 0o555
          tar.file "files/data", content: "data"
          tar.directory "files", mode: 0o750
          tar.file "after", content: "after"
        end
        extract_archive("-p")
        expect(extracted("links")).to have_mode(0o555)
        expect(extracted("files")).to have_mode(0o750)
        expect(extracted("links/link")).to be_symlink(target: "../files/data")
        expect(File.binread(extracted("links/link"))).to eq("data")
        expect(extracted("after")).to be_file(content: "after")
      end
    end

    describe "extrac24.at", gnu_tar_source: "extrac24.at" do
      it "extracts only file content to stdout without creating directories" do
        write_archive do |tar|
          tar.directory "dir"
          tar.file "dir/file", content: "stdout content"
        end
        expect(run_tar("-xOf", archive_path, "-C", extract_dir)).to eq("stdout content")
        expect(Dir.children(extract_dir)).to be_empty
      end
    end

    describe "recurse.at", gnu_tar_source: "recurse.at" do
      it "writes an explicitly added directory without adding its children from disk" do
        FileUtils.mkdir_p(File.join(work_dir, "source"))
        File.binwrite(File.join(work_dir, "source/child"), "not archived")
        Dir.chdir(work_dir) { write_archive { |tar| tar.directory "source", mode: 0o700 } }
        expect(run_tar("-tf", archive_path)).to eq("source/\n")
        extract_archive
        expect(extracted("source")).to have_mode(0o700)
        expect(Dir.children(extracted("source"))).to be_empty
      end
    end
  end
end
