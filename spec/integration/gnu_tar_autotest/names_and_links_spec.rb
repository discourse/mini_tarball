# frozen_string_literal: true

require_relative "spec_helper"

TarExtractor.extractors.each do |extractor|
  RSpec.describe "GNU tar Autotest names and links (#{extractor.name})", :gnu_tar_autotest do
    include_context "with a GNU tar Autotest workspace"
    let(:tar_binary) { extractor.binary_path }

    describe "long01.at", gnu_tar_source: "long01.at" do
      # Upstream uses a 511-byte name (512 bytes including its NUL terminator).
      # Also exercise either side of both header and extension-block boundaries.
      [99, 100, 101, 255, 256, 511, 512, 513, 1023, 1024, 1025].each do |length|
        it "extracts a #{length}-byte filename and the following member" do
          name = archive_name(length)
          expect(name.bytesize).to eq(length)
          write_archive do |tar|
            tar.file name, content: "long member"
            tar.file "after", content: "following member"
          end

          expect(run_tar("-tf", archive_path).lines.map(&:chomp)).to eq([name, "after"])
          skip_unless_extractable(name)
          extract_archive
          expect(extracted(name)).to be_file(content: "long member")
          expect(extracted("after")).to be_file(content: "following member")
        end
      end

      [100, 101, 511, 512, 513, 1023].each do |length|
        %i[symlink hardlink].each do |type|
          it "extracts #{type} names and targets of #{length} bytes without consuming the next member" do
            target = "t#{archive_name(length - 1)}"
            name = "l#{archive_name(length - 1)}"
            source = type == :symlink ? File.join(File.dirname(name), target) : target
            write_archive do |tar|
              tar.file source, content: "linked content"
              if type == :symlink
                tar.symlink(name, target:)
              else
                tar.hardlink(name, target:)
              end
              tar.file "after", content: "after link"
            end

            skip_unless_extractable(name, source)
            extract_archive
            if type == :symlink
              expect(extracted(name)).to be_symlink(target:)
              expect(File.binread(extracted(name))).to eq("linked content")
            else
              expect(extracted(name)).to be_hardlink_of(extracted(target))
              expect(File.binread(extracted(name))).to eq("linked content")
            end
            expect(extracted("after")).to be_file(content: "after link")
          end
        end
      end

      it "extracts a directory with an extension-block-sized name" do
        name = archive_name(511)
        write_archive do |tar|
          tar.directory name
          tar.file "#{name}/child", content: "child"
          tar.file "after", content: "after directory"
        end
        extract_archive
        expect(extracted(name)).to be_dir
        expect(extracted("#{name}/child")).to be_file(content: "child")
        expect(extracted("after")).to be_file(content: "after directory")
      end
    end

    describe "link02.at", gnu_tar_source: "link02.at" do
      it "preserves all hardlinks to the first file" do
        write_archive do |tar|
          tar.file "original", content: "shared data" * 64
          %w[first second third].each { |name| tar.hardlink name, target: "original" }
        end
        extract_archive
        %w[first second third].each do |name|
          expect(extracted(name)).to be_hardlink_of(extracted("original"))
          expect(File.binread(extracted(name))).to eq("shared data" * 64)
        end
      end
    end

    describe "link04.at", gnu_tar_source: "link04.at" do
      it "restores duplicate directory and symlink members" do
        write_archive do |tar|
          2.times do
            tar.directory "dir"
            tar.file "dir/file", content: "original"
            tar.symlink "dir/link", target: "file"
          end
        end
        extract_archive
        expect(extracted("dir/file")).to be_file(content: "original")
        expect(extracted("dir/link")).to be_symlink(target: "file")
      end

      it "preserves a hardlink to a symlink as a symlink inode" do
        write_archive do |tar|
          tar.file "target", content: "content"
          tar.symlink "link", target: "target"
          tar.hardlink "alias", target: "link"
        end
        extract_archive
        expect(extracted("link")).to be_symlink(target: "target")
        expect(extracted("alias")).to be_symlink(target: "target")
        expect(File.lstat(extracted("alias")).ino).to eq(File.lstat(extracted("link")).ino)
      end
    end

    describe "incr01.at", gnu_tar_source: "incr01.at" do
      it "restores a dangling symlink without requiring its target" do
        write_archive { |tar| tar.symlink "dangling", target: "missing" }
        extract_archive
        expect(extracted("dangling")).to be_symlink(target: "missing")
        expect(File.exist?(extracted("missing"))).to be false
      end
    end

    describe "add-file.at and T-null2.at", gnu_tar_source: %w[add-file.at T-null2.at] do
      it "preserves names with leading dashes, spaces and backslashes verbatim" do
        names = ["-file", "--option value", "space name", "colon:\\image.jpg"]
        write_archive { |tar| names.each { |name| tar.file name, content: name } }
        extract_archive
        names.each { |name| expect(extracted(name)).to be_file(content: name) }
      end
    end
  end
end
