require 'tempfile'

RSpec.describe CleanupVendor do
  let(:dir) { Pathname.new(Dir.mktmpdir('cleanup_vendor')) }

  it 'has a version number' do
    expect(CleanupVendor::VERSION).not_to be nil
  end

  describe '.run' do
    let!(:extensions) do
      %w[c cpp gem h hpp java log md mk o rdoc txt].map do |ext|
        file = Tempfile.create(['test', ".#{ext}"], Dir.mktmpdir('kept', dir))
        Pathname.new(file).relative_path_from(dir).to_s
      end
    end

    let!(:files) do
      %w[README Makefile LICENSE].map do |file|
        FileUtils.touch(File.join(dir, file))
        file
      end
    end

    let!(:dirs) do
      %w[.git .github spec].map do |d|
        subdir = File.join(dir, d)
        Dir.mkdir(subdir)
        Tempfile.create('test', subdir)
        d
      end
    end

    let!(:non_top_level_directories) do
      topdir = Dir.mktmpdir('kept', dir)

      %w[spec].map do |d|
        subdir = File.join(topdir, d)
        Dir.mkdir(subdir)
        Tempfile.create('test', subdir)
        Pathname.new(subdir).relative_path_from(dir).to_s
      end
    end

    let(:all_files) { files + dirs + extensions }

    before { FileUtils.touch(File.join(dir, 'kept.gemspec')) }
    after { FileUtils.remove_entry(dir) }

    context 'without dry-run' do
      it 'should remove all matching entries' do
        described_class.run(dir)

        Dir.chdir(dir) do
          files = Dir.glob('**/*', File::FNM_DOTMATCH).grep_v('.')
          expect(files).to all(satisfy { |f| f.start_with?('kept') })
          expect(files).to include(*non_top_level_directories)
        end
      end
    end

    context 'with summary' do
      it 'should display a nice summary' do
        expected_count = all_files.count
        expect { described_class.run(dir, summary: true) }.to output(/Summary:\s+Removed files:\s+#{expected_count}/).to_stdout
      end
    end

    context 'with dry run' do
      it 'should keep all the entries' do
        expect { described_class.run(dir, dry_run: true) }.to output(/Removing/).to_stdout

        Dir.chdir(dir) do
          left_files = Dir.glob('**/*', File::FNM_DOTMATCH)

          expect(left_files).to include(*files)
          expect(left_files).to include(*dirs)
          expect(left_files).to include(*extensions)
        end
      end
    end
  end

  describe '.filter' do
    it 'should throw an error when called with a nil' do
      expect { described_class.filter(nil) }.to raise_error(CleanupVendor::Error)
    end

    it 'should throw an error when called with a file' do
      expect { described_class.filter(__FILE__) }.to raise_error(CleanupVendor::Error)
    end

    context 'when called with a real directory' do
      let!(:rb) { Tempfile.create(['test', '.rb'], dir) }
      let!(:spec) { Dir.mkdir(File.join(dir, 'spec')) }
      let!(:fix_filename) { File.basename(Tempfile.create('test', dir).path) }

      it 'without options it should return with an empty list' do
        expect { described_class.filter(dir).to be_empty }
      end

      it { expect { |b| described_class.filter(dir, extensions: %w[rb], &b) }.to yield_control }

      it 'should filter for extensions' do
        entries = described_class.filter(dir, extensions: %w[rb])

        expect(entries).to all(satisfy { |f| File.file?(f) && f.end_with?('rb') })
      end

      it 'should filter for directories' do
        entries = described_class.filter(dir, directories: %w[spec])

        expect(entries).to all(satisfy { |f| File.directory?(f) && %w[spec].include?(File.basename(f)) })
      end

      it 'should filter for filenames' do
        expect { |b| described_class.filter(dir, filenames: [fix_filename], &b) }.to yield_with_args(fix_filename)
      end
    end
  end
end
