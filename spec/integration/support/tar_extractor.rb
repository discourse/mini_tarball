# frozen_string_literal: true

module TarExtractor
  Extractor = Data.define(:name, :binary_path)

  ExtractionContext =
    Data.define(:extractor, :extract_dir) do
      def name = extractor.name

      def extract(archive_path, gzip: false)
        flags = gzip ? "-xzf" : "-xf"
        system(
          extractor.binary_path,
          flags,
          archive_path,
          "-C",
          extract_dir,
          out: File::NULL,
          err: File::NULL,
        )
      end
    end

  class << self
    def extractors
      list = []
      list << Extractor.new(name: "gnu tar", binary_path: GnuTar.binary_path) if GnuTar.available?
      list << Extractor.new(name: "bsdtar", binary_path: BsdTar.binary_path) if BsdTar.available?
      list
    end

    def each_extractor(tmpdir:)
      extractors.each do |extractor|
        extract_dir = File.join(tmpdir, "extracted_#{extractor.name.tr(" ", "_")}")
        FileUtils.mkdir_p(extract_dir)
        yield ExtractionContext.new(extractor:, extract_dir:)
      end
    end
  end
end
