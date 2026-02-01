# frozen_string_literal: true

RSpec.describe MiniTarball::PlaceholderManager do
  let(:attrs) { MiniTarball::EntryAttributes.with_file_defaults }

  def build_manager(io)
    header_writer = MiniTarball::HeaderWriter.new(MiniTarball::WriteOnlyStream.new(io))
    content_writer = MiniTarball::ContentWriter.new(io, header_writer)
    described_class.new(io, header_writer, content_writer)
  end

  it "raises when filling a placeholder from another manager" do
    manager_one = build_manager(StringIO.new.binmode)
    manager_two = build_manager(StringIO.new.binmode)

    placeholder = manager_one.reserve(name: "file.txt", size: 10)

    expect { manager_two.fill(placeholder, attrs) { |stream| stream.write("x") } }.to raise_error(
      ArgumentError,
      "Placeholder does not belong to this writer",
    )
  end
end
