#------------------------------------------------------------------------------
# File:         Flash.pm
#
# Description:  Read Shockwave Flash meta information
#
# Revisions:    05/16/2006 - P. Harvey Created
#               06/07/2007 - PH Added support for FLV (Flash Video) files
#
# References:   1) http://www.the-labs.com/MacromediaFlash/SWF-Spec/SWFfileformat.html
#               2) http://sswf.sourceforge.net/SWFalexref.html
#               3) http://osflash.org/flv/
#               4) http://www.irisa.fr/texmex/people/dufouil/ffmpegdoxy/flv_8h.html
#
# Notes:        I'll add AMF3 support if someone sends me a FLV with AMF3 data
#------------------------------------------------------------------------------

package Image::ExifTool::Flash;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::FLAC;

$VERSION = '1.04';

sub ProcessMeta($$$;$);

# information extracted from SWF header
%Image::ExifTool::Flash::Main = (
    GROUPS => { 2 => 'Video' },
    NOTES => q{
        The information below is extracted from the header of SWF (Shockwave Flash)
        files.
    },
    FlashVersion => { },
    Compressed   => { PrintConv => { 0 => 'False', 1 => 'True' } },
    ImageWidth   => { },
    ImageHeight  => { },
    FrameRate    => { },
    FrameCount   => { },
    Duration => {
        Notes => 'calculated from FrameRate and FrameCount',
        PrintConv => 'ConvertDuration($val)',
    },
);

# packets in Flash Video files
%Image::ExifTool::Flash::FLV = (
    NOTES => q{
        Information is extracted from the following packets in FLV (Flash Video)
        files.
    },
    0x08 => {
        Name => 'Audio',
        BitMask => 0x04,
        SubDirectory => { TagTable => 'Image::ExifTool::Flash::Audio' },
    },
    0x09 => {
        Name => 'Video',
        BitMask => 0x01,
        SubDirectory => { TagTable => 'Image::ExifTool::Flash::Video' },
    },
    0x12 => {
        Name => 'Meta',
        SubDirectory => { TagTable => 'Image::ExifTool::Flash::Meta' },
    },
);

# tags in Flash Video packet header
%Image::ExifTool::Flash::Audio = (
    PROCESS_PROC => \&Image::ExifTool::FLAC::ProcessBitStream,
    GROUPS => { 2 => 'Audio' },
    NOTES => 'Information extracted from the Flash Audio header.',
    'Bit0-3' => {
        Name => 'AudioEncoding',
        PrintConv => {
            0 => 'PCM-BE (uncompressed)', # PCM-BE according to ref 4
            1 => 'ADPCM',
            2 => 'MP3',
            3 => 'PCM-LE (uncompressed)', #4
            5 => 'Nellymoser 8kHz Mono',
            6 => 'Nellymoser',
        },
    },
    'Bit4-5' => {
        Name => 'AudioSampleRate',
        ValueConv => {
            0 => 5512,
            1 => 11025,
            2 => 22050,
            3 => 44100,
        },
    },
    'Bit6' => {
        Name => 'AudioSampleBits',
        ValueConv => '8 * ($val + 1)',
    },
    'Bit7' => {
        Name => 'AudioChannels',
        ValueConv => '$val + 1',
        PrintConv => {
            1 => '1 (mono)',
            2 => '2 (stereo)',
        },
    },
);

# tags in Flash Video packet header
%Image::ExifTool::Flash::Video = (
    PROCESS_PROC => \&Image::ExifTool::FLAC::ProcessBitStream,
    GROUPS => { 2 => 'Video' },
    NOTES => 'Information extracted from the Flash Video header.',
    'Bit4-7' => {
        Name => 'VideoEncoding',
        PrintConv => {
            2 => 'Sorensen H.263',
            3 => 'Screen Video',
            4 => 'On2 VP6',
            5 => 'On2 VP6 Alpha', #3
            6 => 'Screen Video 2', #3
        },
    },
);

# tags in Flash META packet (in ActionScript Message Format)
%Image::ExifTool::Flash::Meta = (
    PROCESS_PROC => \&ProcessMeta,
    GROUPS => { 2 => 'Video' },
    NOTES => q{
        Below are a few observed FLV Meta tags, but ExifTool will attempt to extract
        information from any tag found.
    },
    'audiocodecid'  => { Name => 'AudioCodecID',    Groups => { 2 => 'Audio' } },
    'audiodatarate' => {
        Name => 'AudioBitrate',
        Groups => { 2 => 'Audio' },
        ValueConv => '$val * 1000',
        PrintConv => 'int($val + 0.5)',
    },
    'audiodelay'    => { Name => 'AudioDelay',      Groups => { 2 => 'Audio' } },
    'audiosamplerate'=>{ Name => 'AudioSampleRate', Groups => { 2 => 'Audio' } },
    'audiosamplesize'=>{ Name => 'AudioSampleSize', Groups => { 2 => 'Audio' } },
    'audiosize'     => { Name => 'AudioSize',       Groups => { 2 => 'Audio' } },
    'canSeekToEnd'  => 'CanSeekToEnd',
    'creationdate'  => {
        # (not an AMF date type in my sample)
        Name => 'CreateDate',
        Groups => { 2 => 'Time' },
        ValueConv => '$val=~s/\s+$//; $val',    # trim trailing whitespace
    },
    'cuePoints'     => {
        Name => 'CuePoint',
        SubDirectory => { TagTable => 'Image::ExifTool::Flash::CuePoint' },
    },
    'datasize'      => 'DataSize',
    'duration' => {
        Name => 'Duration',
        PrintConv => 'ConvertDuration($val)',
    },
    'filesize'      => 'FileSizeBytes',
    'framerate'     => {
        Name => 'FrameRate',
        PrintConv => 'int($val * 1000 + 0.5) / 1000',
    },
    'hasAudio'      => { Name => 'HasAudio',        Groups => { 2 => 'Audio' } },
    'hasCuePoints'  => 'HasCuePoints',
    'hasKeyframes'  => 'HasKeyFrames',
    'hasMetadata'   => 'HasMetadata',
    'hasVideo'      => 'HasVideo',
    'height'        => 'ImageHeight',
    'keyframesTimes'=> 'KeyFramesTimes',
    'keyframesFilepositions' => 'KeyFramePositions',
    'lasttimestamp' => 'LastTimeStamp',
    'lastkeyframetimestamp' => 'LastKeyFrameTime',
    'metadatacreator'=>'MetadataCreator',
    'metadatadate'  => {
        Name => 'MetadataDate',
        Groups => { 2 => 'Time' },
        PrintConv => '$self->ConvertDateTime($val)',
    },
    'stereo'        => { Name => 'Stereo',          Groups => { 2 => 'Audio' } },
    'videocodecid'  => 'VideoCodecID',
    'videodatarate' => {
        Name => 'VideoBitrate',
        ValueConv => '$val * 1000',
        PrintConv => 'int($val + 0.5)',
    },
    'videosize'     => 'VideoSize',
    'width'         => 'ImageWidth',
);

# tags in Flash META CuePoint structure
%Image::ExifTool::Flash::CuePoint = (
    PROCESS_PROC => \&ProcessMeta,
    GROUPS => { 2 => 'Video' },
    NOTES => q{
        These tag names are added to the CuePoint name to generate complete tag
        names like "CuePoint0Name".
    },
    'name' => 'Name',
    'type' => 'Type',
    'time' => 'Time',
    'parameters' => {
        Name => 'Parameter',
        SubDirectory => { TagTable => 'Image::ExifTool::Flash::Parameter' },
    },
);

# tags in Flash META CuePoint Parameter structure
%Image::ExifTool::Flash::Parameter = (
    PROCESS_PROC => \&ProcessMeta,
    GROUPS => { 2 => 'Video' },
    NOTES => q{
        There are no pre-defined parameter tags, but ExifTool will extract any
        existing parameters, with tag names like "CuePoint0ParameterXxx".
    },
);

# name lookup for known AMF data types
my @amfType = qw(double boolean string object movieClip null undefined reference
                 mixedArray objectEnd array date longString unsupported recordSet
                 XML typedObject AMF3data);

# test for AMF structure types (object, mixed array or typed object)
my %isStruct = ( 0x03 => 1, 0x08 => 1, 0x10 => 1 );

#------------------------------------------------------------------------------
# Process Flash Video AMF Meta packet (ref 3)
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
#         3) Set to extract single type/value only
# Returns: 1 on success, (or type/value if extracting single value)
# Notes: Updates DataPos in dirInfo if extracting single value
sub ProcessMeta($$$;$)
{
    my ($exifTool, $dirInfo, $tagTablePtr, $single) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dataPos = $$dirInfo{DataPos};
    my $dirLen = $$dirInfo{DirLen} || length($$dataPt);
    my $pos = $$dirInfo{Pos} || 0;
    my $verbose = $exifTool->Options('Verbose');
    my ($type, $val, $rec);

    $exifTool->VerboseDir('Meta') unless $single;

Record: for ($rec=0; ; ++$rec) {
        last if $pos >= $dirLen;
        $type = ord(substr($$dataPt, $pos));
        ++$pos;
        if ($type == 0x00 or $type == 0x0b) {   # double or date
            last if $pos + 8 > $dirLen;
            $val = GetDouble($dataPt, $pos);
            $pos += 8;
            if ($type == 0x0b) {    # date
                $val /= 1000;       # convert to seconds
                my $frac = $val - int($val);    # fractional seconds
                # get time zone
                last if $pos + 2 > $dirLen;
                my $tz = Get16s($dataPt, $pos);
                $pos += 2;
                # construct date/time string
                $val = Image::ExifTool::ConvertUnixTime(int($val));
                if ($frac) {
                    $frac = sprintf('%.6f', $frac);
                    $frac =~ s/(^0|0+$)//g;
                    $val .= $frac;
                }
                # add timezone
                if ($tz < 0) {
                    $val .= '-';
                    $tz *= -1;
                } else {
                    $val .= '+';
                }
                $val .= sprintf('%.2d:%.2d', int($tz/60), $tz%60);
            }
        } elsif ($type == 0x01) {   # boolean
            last if $pos + 1 > $dirLen;
            $val = Get8u($dataPt, $pos);
            $val = { 0 => 'No', 1 => 'Yes' }->{$val} if $val < 2;
            ++$pos;
        } elsif ($type == 0x02) {   # string
            last if $pos + 2 > $dirLen;
            my $len = Get16u($dataPt, $pos);
            last if $pos + 2 + $len > $dirLen;
            $val = substr($$dataPt, $pos + 2, $len);
            $pos += 2 + $len;
        } elsif ($isStruct{$type}) {   # object, mixed array or typed object
            $exifTool->VPrint(1, "  + [$amfType[$type]]\n");
            my $getName;
            $val = '';  # dummy value
            if ($type == 0x08) {        # mixed array
                # skip last array index for mixed array
                last if $pos + 4 > $dirLen;
                $pos += 4;
            } elsif ($type == 0x10) {   # typed object
                $getName = 1;
            }
            for (;;) {
                # get tag ID (or typed object name)
                last Record if $pos + 2 > $dirLen;
                my $len = Get16u($dataPt, $pos);
                if ($pos + 2 + $len > $dirLen) {
                    $exifTool->Warn("Truncated $amfType[$type] record");
                    last Record;
                }
                my $tag = substr($$dataPt, $pos + 2, $len);
                $pos += 2 + $len;
                # first string of a typed object is the object name
                if ($getName) {
                    $exifTool->VPrint(1,"  | (object name '$tag')\n");
                    undef $getName;
                    next; # (ignore name for now)
                }
                my $subTablePtr = $tagTablePtr;
                my $tagInfo = $$subTablePtr{$tag};
                # switch to subdirectory table if necessary
                if ($tagInfo and $$tagInfo{SubDirectory}) {
                    $tag = $$tagInfo{Name}; # use our name for the tag
                    $subTablePtr = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
                }
                # get object value
                my $valPos = $pos + 1;
                $$dirInfo{Pos} = $pos;
                my $structName = $$dirInfo{StructName};
                # add structure name to start of tag name
                $tag = $structName . ucfirst($tag) if defined $structName;
                $$dirInfo{StructName} = $tag;       # set new structure name
                my ($t, $v) = ProcessMeta($exifTool, $dirInfo, $subTablePtr, 1);
                $$dirInfo{StructName} = $structName;# restore original structure name
                $pos = $$dirInfo{Pos};  # update to new position in packet
                # all done if this value contained tags
                last Record unless defined $t and defined $v;
                next if $isStruct{$t};  # already handled tags in sub-structures
                next if ref($v) eq 'ARRAY' and not @$v; # ignore empty arrays
                last if $t == 0x09; # (end of object)
                if (not $$subTablePtr{$tag} and $tag =~ /^\w+$/) {
                    Image::ExifTool::AddTagToTable($subTablePtr, $tag, { Name => ucfirst($tag) });
                    $verbose > 1 and $exifTool->VPrint(1, "  | (adding $tag)\n");
                }
                $exifTool->HandleTag($subTablePtr, $tag, $v,
                    DataPt  => $dataPt,
                    DataPos => $dataPos,
                    Start   => $valPos,
                    Size    => $pos - $valPos,
                    Format  => $amfType[$t] || sprintf('0x%x',$t),
                );
            }
      # } elsif ($type == 0x04) {   # movie clip (not supported)
        } elsif ($type == 0x05 or $type == 0x06 or $type == 0x09 or $type == 0x0d) {
            # null, undefined, dirLen of object, or unsupported
            $val = '';
        } elsif ($type == 0x07) {   # reference
            last if $pos + 2 > $dirLen;
            $val = Get16u($dataPt, $pos);
            $pos += 2;
        } elsif ($type == 0x0a) {   # array
            last if $pos + 4 > $dirLen;
            my $num = Get32u($dataPt, $pos);
            $$dirInfo{Pos} = $pos + 4;
            my ($i, @vals);
            # add array index to compount tag name
            my $structName = $$dirInfo{StructName};
            for ($i=0; $i<$num; ++$i) {
                $$dirInfo{StructName} = $structName . $i if defined $structName;
                my ($t, $v) = ProcessMeta($exifTool, $dirInfo, $tagTablePtr, 1);
                last Record unless defined $v;
                # save value unless contained in a sub-structure
                push @vals, $v unless $isStruct{$t};
            }
            $$dirInfo{StructName} = $structName;
            $pos = $$dirInfo{Pos};
            $val = \@vals;
        } elsif ($type == 0x0c or $type == 0x0f) {  # long string or XML
            last if $pos + 4 > $dirLen;
            my $len = Get32u($dataPt, $pos);
            last if $pos + 4 + $len > $dirLen;
            $val = substr($$dataPt, $pos + 4, $len);
            $pos += 4 + $len;
      # } elsif ($type == 0x0e) {   # record set (not supported)
      # } elsif ($type == 0x11) {   # AMF3 data (can't add support for this without a test sample)
        } else {
            my $t = $amfType[$type] || sprintf('type 0x%x',$type);
            $exifTool->Warn("AMF $t record not yet supported");
            undef $type;    # (so we don't print another warning)
            last;           # can't continue
        }
        last if $single;        # all done if extracting single value
        unless ($isStruct{$type}) {
            # only process "onMetaData" Meta packets
            if ($type == 0x02 and not $rec) {
                my $verb = ($val eq 'onMetaData') ? 'processing' : 'ignoring';
                $exifTool->VPrint(0, "  | ($verb $val information)\n");
                last unless $val eq 'onMetaData';
            } else {
                # give verbose indication if we ignore a lone value
                my $t = $amfType[$type] || sprintf('type 0x%x',$type);
                $exifTool->VPrint(1, "  | (ignored lone $t value '$val')\n");
            }
        }
    }
    if (not defined $val and defined $type) {
        $exifTool->Warn(sprintf("Truncated AMF record 0x%x",$type));
    }
    return 1 unless $single;    # all done
    $$dirInfo{Pos} = $pos;      # update position
    return($type,$val);         # return single type/value pair
}

#------------------------------------------------------------------------------
# Read information frame a Flash Video file
# Inputs: 0) ExifTool object reference, 1) Directory information reference
# Returns: 1 on success, 0 if this wasn't a valid Flash Video file
sub ProcessFLV($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $raf = $$dirInfo{RAF};
    my $buff;

    $raf->Read($buff, 9) == 9 or return 0;
    $buff =~ /^FLV\x01/ or return 0;
    SetByteOrder('MM');
    $exifTool->SetFileType();
    my ($flags, $offset) = unpack('x4CN', $buff);
    $raf->Seek($offset-9, 1) or return 1 if $offset > 9;
    $flags &= 0x05; # only look for audio/video
    my $found = 0;
    my $tagTablePtr = GetTagTable('Image::ExifTool::Flash::FLV');
    for (;;) {
        $raf->Read($buff, 15) == 15 or last;
        my $len = unpack('x4N', $buff);
        my $type = $len >> 24;
        $len &= 0x00ffffff;
        my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $type);
        if ($verbose > 1) {
            my $name = $tagInfo ? $$tagInfo{Name} : "type $type";
            $exifTool->VPrint(1, "FLV $name packet, len $len\n");
        }
        undef $buff;
        if ($tagInfo and $$tagInfo{SubDirectory}) {
            my $mask = $$tagInfo{BitMask};
            if ($mask) {
                # handle audio or video packet
                unless ($found & $mask) {
                    $found |= $mask;
                    $flags &= ~$mask;
                    if ($len>=1 and $raf->Read($buff, 1) == 1) {
                        $len -= 1;
                    } else {
                        $exifTool->Warn("Bad $$tagInfo{Name} packet");
                        last;
                    }
                }
            } elsif ($raf->Read($buff, $len) == $len) {
                $len = 0;
            } else {
                $exifTool->Warn('Truncated Meta packet');
                last;
            }
        }
        if (defined $buff) {
            $exifTool->HandleTag($tagTablePtr, $type, undef,
                DataPt  => \$buff,
                DataPos => $raf->Tell() - length($buff),
            );
        }
        last unless $flags;
        $raf->Seek($len, 1) or last if $len;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Found a Flash tag
# Inputs: 0) ExifTool object ref, 1) tag name, 2) tag value
sub FoundFlashTag($$$)
{
    my ($exifTool, $tag, $val) = @_;
    $exifTool->HandleTag(\%Image::ExifTool::Flash::Main, $tag, $val);
}

#------------------------------------------------------------------------------
# Read information frame a Flash file
# Inputs: 0) ExifTool object reference, 1) Directory information reference
# Returns: 1 on success, 0 if this wasn't a valid Flash file
sub ProcessSWF($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $raf = $$dirInfo{RAF};
    my $buff;

    $raf->Read($buff, 8) == 8 or return 0;
    $buff =~ /^(F|C)WS([^\0])/ or return 0;
    my ($compressed, $vers) = ($1 eq 'C' ? 1 : 0, ord($2));

    # read the first bit of the file
    $raf->Read($buff, 64) or return 0;

    $exifTool->SetFileType();
    GetTagTable('Image::ExifTool::Flash::Main');  # make sure table is initialized

    FoundFlashTag($exifTool, FlashVersion => $vers);
    FoundFlashTag($exifTool, Compressed => $compressed);

    # uncompress if necessary
    if ($compressed) {
        unless (eval 'require Compress::Zlib') {
            $exifTool->Warn('Install Compress::Zlib to extract compressed information');
            return 1;
        }
        my $inflate = Compress::Zlib::inflateInit();
        my $tmp = $buff;
        $buff = '';
        # read file 64 bytes at a time and inflate until we get enough uncompressed data
        for (;;) {
            unless ($inflate) {
                $exifTool->Warn('Error inflating compressed Flash data');
                return 1;
            }
            my ($dat, $stat) = $inflate->inflate($tmp);
            if ($stat == Compress::Zlib::Z_STREAM_END() or
                $stat == Compress::Zlib::Z_OK())
            {
                $buff .= $dat;  # add inflated data to buffer
                last if length $buff >= 64 or $stat == Compress::Zlib::Z_STREAM_END();
                $raf->Read($tmp,64) or last;    # read some more data
            } else {
                undef $inflate; # issue warning the next time around
            }
        }
    }
    # unpack elements of bit-packed Flash Rect structure
    my ($nBits, $totBits, $nBytes);
    for (;;) {
        if (length($buff)) {
            $nBits = unpack('C', $buff) >> 3;    # bits in x1,x2,y1,y2 elements
            $totBits = 5 + $nBits * 4;           # total bits in Rect structure
            $nBytes = int(($totBits + 7) / 8);   # byte length of Rect structure
            last if length $buff >= $nBytes + 4; # make sure header is long enough
        }
        $exifTool->Warn('Truncated Flash file');
        return 1;
    }
    my $bits = unpack("B$totBits", $buff);
    # isolate Rect elements and convert from ASCII bit strings to integers
    my @vals = unpack('x5' . "a$nBits" x 4, $bits);
    # (do conversion the hard way because oct("0b$val") requires Perl 5.6)
    map { $_ = unpack('N', pack('B32', '0' x (32 - length $_) . $_)) } @vals;

    # calculate and store ImageWidth/Height
    FoundFlashTag($exifTool, ImageWidth  => ($vals[1] - $vals[0]) / 20);
    FoundFlashTag($exifTool, ImageHeight => ($vals[3] - $vals[2]) / 20);

    # get frame rate and count
    @vals = unpack("x${nBytes}v2", $buff);
    FoundFlashTag($exifTool, FrameRate => $vals[0] / 256);
    FoundFlashTag($exifTool, FrameCount => $vals[1]);
    FoundFlashTag($exifTool, Duration => $vals[1] * 256 / $vals[0]) if $vals[0];

    return 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::Flash - Read Shockwave Flash meta information

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to read SWF
(Shockwave Flash) and FLV (Flash Video) files.

=head1 NOTES

Flash Video AMF3 support has not yet been added because I haven't yet found
a FLV file containing AMF3 information.  If someone sends me a sample then I
will add AMF3 support.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.the-labs.com/MacromediaFlash/SWF-Spec/SWFfileformat.html>

=item L<http://sswf.sourceforge.net/SWFalexref.html>

=item L<http://osflash.org/flv/>

=item L<http://www.irisa.fr/texmex/people/dufouil/ffmpegdoxy/flv_8h.html>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Flash Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
