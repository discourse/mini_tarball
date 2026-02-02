# frozen_string_literal: true

module TarExtractor
  Extractor = Data.define(:name, :binary_path)

  class << self
    def extractors
      list = []
      list << Extractor.new(name: "gnu tar", binary_path: GnuTar.binary_path) if GnuTar.available?
      list << Extractor.new(name: "bsdtar", binary_path: BsdTar.binary_path) if BsdTar.available?
      list
    end

    def each_extractor(tmpdir: nil)
      extractors.each do |extractor|
        extract_dir = tmpdir && extract_dir_for(extractor, within: tmpdir)
        yield extractor, extract_dir
      end
    end

    def extract(archive_path, destination:, extractor:, gzip: false)
      flags = gzip ? "-xzf" : "-xf"
      system(
        extractor.binary_path,
        flags,
        archive_path,
        "-C",
        destination,
        out: File::NULL,
        err: File::NULL,
      )
    end

    private

    def extract_dir_for(extractor, within:)
      dir = File.join(within, "extracted_#{extractor.name.tr(" ", "_")}")
      FileUtils.mkdir_p(dir)
      dir
    end
  end
end
