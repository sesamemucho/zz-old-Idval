#------------------------------------------------------------------------------
# File:         IPTC.pm
#
# Description:  Read IPTC meta information
#
# Revisions:    Jan. 08/03 - P. Harvey Created
#               Feb. 05/04 - P. Harvey Added support for records other than 2
#
# References:   1) http://www.iptc.org/IIM/
#------------------------------------------------------------------------------

package Image::ExifTool::IPTC;

use strict;
use vars qw($VERSION $AUTOLOAD %iptcCharset);

$VERSION = '1.24';

%iptcCharset = (
    "\x1b%G"  => 'UTF8',
   # don't translate these (at least until we handle ISO 2022 shift codes)
   # because the sets are only designated and not invoked 
   # "\x1b,A"  => 'Latin',  # G0 = ISO 8859-1 (similar to Latin1, but codes 0x80-0x9f are missing)
   # "\x1b-A"  => 'Latin',  # G1     "
   # "\x1b.A"  => 'Latin',  # G2
   # "\x1b/A"  => 'Latin',  # G3
);

sub ProcessIPTC($$$);
sub WriteIPTC($$$);
sub CheckIPTC($$$);
sub PrintCodedCharset($);
sub PrintInvCodedCharset($);

my %fileFormat = (
    0 => 'No ObjectData',
    1 => 'IPTC-NAA Digital Newsphoto Parameter Record',
    2 => 'IPTC7901 Recommended Message Format',
    3 => 'Tagged Image File Format (Adobe/Aldus Image data)',
    4 => 'Illustrator (Adobe Graphics data)',
    5 => 'AppleSingle (Apple Computer Inc)',
    6 => 'NAA 89-3 (ANPA 1312)',
    7 => 'MacBinary II',
    8 => 'IPTC Unstructured Character Oriented File Format (UCOFF)',
    9 => 'United Press International ANPA 1312 variant',
    10 => 'United Press International Down-Load Message',
    11 => 'JPEG File Interchange (JFIF)',
    12 => 'Photo-CD Image-Pac (Eastman Kodak)',
    13 => 'Bit Mapped Graphics File [.BMP] (Microsoft)',
    14 => 'Digital Audio File [.WAV] (Microsoft & Creative Labs)',
    15 => 'Audio plus Moving Video [.AVI] (Microsoft)',
    16 => 'PC DOS/Windows Executable Files [.COM][.EXE]',
    17 => 'Compressed Binary File [.ZIP] (PKWare Inc)',
    18 => 'Audio Interchange File Format AIFF (Apple Computer Inc)',
    19 => 'RIFF Wave (Microsoft Corporation)',
    20 => 'Freehand (Macromedia/Aldus)',
    21 => 'Hypertext Markup Language [.HTML] (The Internet Society)',
    22 => 'MPEG 2 Audio Layer 2 (Musicom), ISO/IEC',
    23 => 'MPEG 2 Audio Layer 3, ISO/IEC',
    24 => 'Portable Document File [.PDF] Adobe',
    25 => 'News Industry Text Format (NITF)',
    26 => 'Tape Archive [.TAR]',
    27 => 'Tidningarnas Telegrambyra NITF version (TTNITF DTD)',
    28 => 'Ritzaus Bureau NITF version (RBNITF DTD)',
    29 => 'Corel Draw [.CDR]',
);

# main IPTC tag table
# Note: ALL entries in main IPTC table (except PROCESS_PROC) must be SubDirectory
# entries, each specifying a TagTable.
%Image::ExifTool::IPTC::Main = (
    GROUPS => { 2 => 'Image' },
    PROCESS_PROC => \&ProcessIPTC,
    WRITE_PROC => \&WriteIPTC,
    1 => {
        Name => 'IPTCEnvelope',
        SubDirectory => {
            TagTable => 'Image::ExifTool::IPTC::EnvelopeRecord',
        },
    },
    2 => {
        Name => 'IPTCApplication',
        SubDirectory => {
            TagTable => 'Image::ExifTool::IPTC::ApplicationRecord',
        },
    },
    3 => {
        Name => 'IPTCNewsPhoto',
        SubDirectory => {
            TagTable => 'Image::ExifTool::IPTC::NewsPhoto',
        },
    },
    7 => {
        Name => 'IPTCPreObjectData',
        SubDirectory => {
            TagTable => 'Image::ExifTool::IPTC::PreObjectData',
        },
    },
    8 => {
        Name => 'IPTCObjectData',
        SubDirectory => {
            TagTable => 'Image::ExifTool::IPTC::ObjectData',
        },
    },
    9 => {
        Name => 'IPTCPostObjectData',
        SubDirectory => {
            TagTable => 'Image::ExifTool::IPTC::PostObjectData',
        },
    },
);

# Record 1 -- EnvelopeRecord
%Image::ExifTool::IPTC::EnvelopeRecord = (
    GROUPS => { 2 => 'Other' },
    WRITE_PROC => \&WriteIPTC,
    CHECK_PROC => \&CheckIPTC,
    WRITABLE => 1,
    0 => {
        Name => 'EnvelopeRecordVersion',
        Format => 'int16u',
    },
    5 => {
        Name => 'Destination',
        Flags => 'List',
        Groups => { 2 => 'Location' },
        Format => 'string[0,1024]',
    },
    20 => {
        Name => 'FileFormat',
        Groups => { 2 => 'Image' },
        Format => 'int16u',
        PrintConv => \%fileFormat,
    },
    22 => {
        Name => 'FileVersion',
        Groups => { 2 => 'Image' },
        Format => 'int16u',
    },
    30 => {
        Name => 'ServiceIdentifier',
        Format => 'string[0,10]',
    },
    40 => {
        Name => 'EnvelopeNumber',
        Format => 'digits[8]',
    },
    50 => {
        Name => 'ProductID',
        Flags => 'List',
        Format => 'string[0,32]',
    },
    60 => {
        Name => 'EnvelopePriority',
        Format => 'digits[1]',
    },
    70 => {
        Name => 'DateSent',
        Groups => { 2 => 'Time' },
        Format => 'digits[8]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifDate($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcDate($val)',
    },
    80 => {
        Name => 'TimeSent',
        Groups => { 2 => 'Time' },
        Format => 'string[11]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifTime($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcTime($val)',
    },
    90 => {
        Name => 'CodedCharacterSet',
        Notes => q{
            values are entered in the form "ESC X Y[, ...]".  The escape sequence for
            UTF-8 character coding is "ESC % G", but this is displayed as "UTF8" for
            convenience.  Either string may be used when writing.  The value of this tag
            affects the decoding of string values in the Application and NewsPhoto
            records
        },
        Format => 'string[0,32]',
        # convert ISO 2022 escape sequences to a more readable format
        PrintConv => \&PrintCodedCharset,
        PrintConvInv => \&PrintInvCodedCharset,
    },
    100 => {
        Name => 'UniqueObjectName',
        Format => 'string[14,80]',
    },
    120 => {
        Name => 'ARMIdentifier',
        Format => 'int16u',
    },
    122 => {
        Name => 'ARMVersion',
        Format => 'int16u',
    },
);

# Record 2 -- ApplicationRecord
%Image::ExifTool::IPTC::ApplicationRecord = (
    GROUPS => { 2 => 'Other' },
    WRITE_PROC => \&WriteIPTC,
    CHECK_PROC => \&CheckIPTC,
    WRITABLE => 1,
    0 => {
        Name => 'ApplicationRecordVersion',
        Format => 'int16u',
    },
    3 => {
        Name => 'ObjectTypeReference',
        Format => 'string[3,67]',
    },
    4 => {
        Name => 'ObjectAttributeReference',
        Flags => 'List',
        Format => 'string[4,68]',
    },
    5 => {
        Name => 'ObjectName',
        Format => 'string[0,64]',
    },
    7 => {
        Name => 'EditStatus',
        Format => 'string[0,64]',
    },
    8 => {
        Name => 'EditorialUpdate',
        Format => 'digits[2]',
    },
    10 => {
        Name => 'Urgency',
        Format => 'digits[1]',
    },
    12 => {
        Name => 'SubjectReference',
        Flags => 'List',
        Format => 'string[13,236]',
    },
    15 => {
        Name => 'Category',
        Format => 'string[0,3]',
    },
    20 => {
        Name => 'SupplementalCategories',
        Flags => 'List',
        Format => 'string[0,32]',
    },
    22 => {
        Name => 'FixtureIdentifier',
        Format => 'string[0,32]',
    },
    25 => {
        Name => 'Keywords',
        Flags => 'List',
        Format => 'string[0,64]',
    },
    26 => {
        Name => 'ContentLocationCode',
        Flags => 'List',
        Groups => { 2 => 'Location' },
        Format => 'string[3]',
    },
    27 => {
        Name => 'ContentLocationName',
        Flags => 'List',
        Groups => { 2 => 'Location' },
        Format => 'string[0,64]',
    },
    30 => {
        Name => 'ReleaseDate',
        Groups => { 2 => 'Time' },
        Format => 'digits[8]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifDate($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcDate($val)',
    },
    35 => {
        Name => 'ReleaseTime',
        Groups => { 2 => 'Time' },
        Format => 'string[11]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifTime($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcTime($val)',
    },
    37 => {
        Name => 'ExpirationDate',
        Groups => { 2 => 'Time' },
        Format => 'digits[8]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifDate($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcDate($val)',
    },
    38 => {
        Name => 'ExpirationTime',
        Groups => { 2 => 'Time' },
        Format => 'string[11]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifTime($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcTime($val)',
    },
    40 => {
        Name => 'SpecialInstructions',
        Format => 'string[0,256]',
    },
    42 => {
        Name => 'ActionAdvised',
        Format => 'digits[2]',
        PrintConv => {
            '' => '',
            '01' => 'Object Kill',
            '02' => 'Object Replace',
            '03' => 'Ojbect Append',
            '04' => 'Object Reference',
        },
    },
    45 => {
        Name => 'ReferenceService',
        Flags => 'List',
        Format => 'string[0,10]',
    },
    47 => {
        Name => 'ReferenceDate',
        Groups => { 2 => 'Time' },
        Flags => 'List',
        Format => 'digits[8]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifDate($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcDate($val)',
    },
    50 => {
        Name => 'ReferenceNumber',
        Flags => 'List',
        Format => 'digits[8]',
    },
    55 => {
        Name => 'DateCreated',
        Groups => { 2 => 'Time' },
        Format => 'digits[8]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifDate($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcDate($val)',
    },
    60 => {
        Name => 'TimeCreated',
        Groups => { 2 => 'Time' },
        Format => 'string[11]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifTime($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcTime($val)',
    },
    62 => {
        Name => 'DigitalCreationDate',
        Groups => { 2 => 'Time' },
        Format => 'digits[8]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifDate($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcDate($val)',
    },
    63 => {
        Name => 'DigitalCreationTime',
        Groups => { 2 => 'Time' },
        Format => 'string[11]',
        Shift => 'Time',
        ValueConv => 'Image::ExifTool::Exif::ExifTime($val)',
        ValueConvInv => 'Image::ExifTool::IPTC::IptcTime($val)',
    },
    65 => {
        Name => 'OriginatingProgram',
        Format => 'string[0,32]',
    },
    70 => {
        Name => 'ProgramVersion',
        Format => 'string[0,10]',
    },
    75 => {
        Name => 'ObjectCycle',
        Format => 'string[1]',
        PrintConv => {
            'a' => 'Morning',
            'p' => 'Evening',
            'b' => 'Both Morning and Evening',
        },
    },
    80 => {
        Name => 'By-line',
        Flags => 'List',
        Format => 'string[0,32]',
        Groups => { 2 => 'Author' },
    },
    85 => {
        Name => 'By-lineTitle',
        Flags => 'List',
        Format => 'string[0,32]',
        Groups => { 2 => 'Author' },
    },
    90 => {
        Name => 'City',
        Format => 'string[0,32]',
        Groups => { 2 => 'Location' },
    },
    92 => {
        Name => 'Sub-location',
        Format => 'string[0,32]',
        Groups => { 2 => 'Location' },
    },
    95 => {
        Name => 'Province-State',
        Format => 'string[0,32]',
        Groups => { 2 => 'Location' },
    },
    100 => {
        Name => 'Country-PrimaryLocationCode',
        Format => 'string[3]',
        Groups => { 2 => 'Location' },
    },
    101 => {
        Name => 'Country-PrimaryLocationName',
        Format => 'string[0,64]',
        Groups => { 2 => 'Location' },
    },
    103 => {
        Name => 'OriginalTransmissionReference',
        Format => 'string[0,32]',
    },
    105 => {
        Name => 'Headline',
        Format => 'string[0,256]',
    },
    110 => {
        Name => 'Credit',
        Groups => { 2 => 'Author' },
        Format => 'string[0,32]',
    },
    115 => {
        Name => 'Source',
        Groups => { 2 => 'Author' },
        Format => 'string[0,32]',
    },
    116 => {
        Name => 'CopyrightNotice',
        Groups => { 2 => 'Author' },
        Format => 'string[0,128]',
    },
    118 => {
        Name => 'Contact',
        Flags => 'List',
        Groups => { 2 => 'Author' },
        Format => 'string[0,128]',
    },
    120 => {
        Name => 'Caption-Abstract',
        Format => 'string[0,2000]',
    },
    121 => { # (format not certain)
        Name => 'LocalCaption',
        Format => 'string[0,256]',
        Notes => q{
            I haven't found a reference for the format of tags 121, 184-188 and
            225-232, so I have just make them writable as strings with
            reasonable length.  Beware that if this is wrong, other utilities
            won't be able to read these tags as written by ExifTool.
        },
    },
    122 => {
        Name => 'Writer-Editor',
        Flags => 'List',
        Groups => { 2 => 'Author' },
        Format => 'string[0,32]',
    },
    125 => {
        Name => 'RasterizedCaption',
        Format => 'string[7360]',
        Binary => 1,
    },
    130 => {
        Name => 'ImageType',
        Groups => { 2 => 'Image' },
        Format => 'string[2]',
    },
    131 => {
        Name => 'ImageOrientation',
        Groups => { 2 => 'Image' },
        Format => 'string[1]',
        PrintConv => {
            P => 'Portrait',
            L => 'Landscape',
            S => 'Square',
        },
    },
    135 => {
        Name => 'LanguageIdentifier',
        Format => 'string[2,3]',
    },
    150 => {
        Name => 'AudioType',
        Format => 'string[2]',
        PrintConv => {
            '1A' => 'Mono Actuality',
            '2A' => 'Stereo Actuality',
            '1C' => 'Mono Question and Answer Session',
            '2C' => 'Stereo Question and Answer Session',
            '1M' => 'Mono Music',
            '2M' => 'Stereo Music',
            '1Q' => 'Mono Response to a Question',
            '2Q' => 'Stereo Response to a Question',
            '1R' => 'Mono Raw Sound',
            '2R' => 'Stereo Raw Sound',
            '1S' => 'Mono Scener',
            '2S' => 'Stereo Scener',
            '0T' => 'Text Only',
            '1V' => 'Mono Voicer',
            '2V' => 'Stereo Voicer',
            '1W' => 'Mono Wrap',
            '2W' => 'Stereo Wrap',
        },
    },
    151 => {
        Name => 'AudioSamplingRate',
        Format => 'digits[6]',
    },
    152 => {
        Name => 'AudioSamplingResolution',
        Format => 'digits[2]',
    },
    153 => {
        Name => 'AudioDuration',
        Format => 'digits[6]',
    },
    154 => {
        Name => 'AudioOutcue',
        Format => 'string[0,64]',
    },
    184 => { # (format not certain)
        Name => 'JobID',
        Format => 'string[0,64]',
    },
    185 => { # (format not certain)
        Name => 'MasterDocumentID',
        Format => 'string[0,256]',
    },
    186 => { # (format not certain)
        Name => 'ShortDocumentID',
        Format => 'string[0,64]',
    },
    187 => { # (format not certain)
        Name => 'UniqueDocumentID',
        Format => 'string[0,128]',
    },
    188 => { # (format not certain)
        Name => 'OwnerID',
        Format => 'string[0,128]',
    },
    200 => {
        Name => 'ObjectPreviewFileFormat',
        Groups => { 2 => 'Image' },
        Format => 'int16u',
        PrintConv => \%fileFormat,
    },
    201 => {
        Name => 'ObjectPreviewFileVersion',
        Groups => { 2 => 'Image' },
        Format => 'int16u',
    },
    202 => {
        Name => 'ObjectPreviewData',
        Groups => { 2 => 'Image' },
        Format => 'string[0,256000]',
        Binary => 1,
    },
    221 => {
        Name => 'Prefs',
        Groups => { 2 => 'Image' },
        Format => 'string[0,64]',
        Notes => 'PhotoMechanic preferences',
        PrintConv => q{
            $val =~ s[\s*(\d+):\s*(\d+):\s*(\d+):\s*(\S*)]
                     [Tagged:$1, ColorClass:$2, Rating:$3, FrameNum:$4];
            return $val;
        },
        PrintConvInv => q{
            $val =~ s[Tagged:\s*(\d+).*ColorClass:\s*(\d+).*Rating:\s*(\d+).*FrameNum:\s*(\S*)]
                     [$1:$2:$3:$4]is;
            return $val;
        },
    },
    225 => { # (format not certain)
        Name => 'ClassifyState',
        Format => 'string[0,64]',
    },
    228 => { # (format not certain)
        Name => 'SimilarityIndex',
        Format => 'string[0,32]',
    },
    230 => { # (format not certain)
        Name => 'DocumentNotes',
        Format => 'string[0,1024]',
    },
    231 => { # (format not certain)
        Name => 'DocumentHistory',
        Format => 'string[0,256]',
    },
    232 => { # (format not certain)
        Name => 'ExifCameraInfo',
        Format => 'string[0,4096]',
    },
);

# Record 3 -- News photo
%Image::ExifTool::IPTC::NewsPhoto = (
    GROUPS => { 2 => 'Image' },
    WRITE_PROC => \&WriteIPTC,
    CHECK_PROC => \&CheckIPTC,
    WRITABLE => 1,
    0 => {
        Name => 'NewsPhotoVersion',
        Format => 'int16u',
    },
    10 => {
        Name => 'IPTCPictureNumber',
        Format => 'string[16]',
        Notes => '4 numbers: 1-Manufacturer ID, 2-Equipment ID, 3-Date, 4-Sequence',
        PrintConv => 'Image::ExifTool::IPTC::ConvertPictureNumber($val)',
        PrintConvInv => 'Image::ExifTool::IPTC::InvConvertPictureNumber($val)',
    },
    20 => {
        Name => 'IPTCImageWidth',
        Format => 'int16u',
    },
    30 => {
        Name => 'IPTCImageHeight',
        Format => 'int16u',
    },
    40 => {
        Name => 'IPTCPixelWidth',
        Format => 'int16u',
    },
    50 => {
        Name => 'IPTCPixelHeight',
        Format => 'int16u',
    },
    55 => {
        Name => 'SupplementalType',
        Format => 'int8u',
        PrintConv => {
            0 => 'Main Image',
            1 => 'Reduced Resolution Image',
            2 => 'Logo',
            3 => 'Rasterized Caption',
        },
    },
    60 => {
        Name => 'ColorRepresentation',
        Format => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x000 => 'No Image, Single Frame',
            0x100 => 'Monochrome, Single Frame',
            0x300 => '3 Components, Single Frame',
            0x301 => '3 Components, Frame Sequential in Multiple Objects',
            0x302 => '3 Components, Frame Sequential in One Object',
            0x303 => '3 Components, Line Sequential',
            0x304 => '3 Components, Pixel Sequential',
            0x305 => '3 Components, Special Interleaving',
            0x400 => '4 Components, Single Frame',
            0x401 => '4 Components, Frame Sequential in Multiple Objects',
            0x402 => '4 Components, Frame Sequential in One Object',
            0x403 => '4 Components, Line Sequential',
            0x404 => '4 Components, Pixel Sequential',
            0x405 => '4 Components, Special Interleaving',
        },
    },
    64 => {
        Name => 'InterchangeColorSpace',
        Format => 'int8u',
        PrintConv => {
            1 => 'X,Y,Z CIE',
            2 => 'RGB SMPTE',
            3 => 'Y,U,V (K) (D65)',
            4 => 'RGB Device Dependent',
            5 => 'CMY (K) Device Dependent',
            6 => 'Lab (K) CIE',
            7 => 'YCbCr',
            8 => 'sRGB',
        },
    },
    65 => {
        Name => 'ColorSequence',
        Format => 'int8u',
    },
    66 => {
        Name => 'ICC_Profile',
        # ...could add SubDirectory support to read into this (if anybody cares)
        Writable => 0,
        Binary => 1,
    },
    70 => {
        Name => 'ColorCalibrationMatrix',
        Writable => 0,
        Binary => 1,
    },
    80 => {
        Name => 'LookupTable',
        Writable => 0,
        Binary => 1,
    },
    84 => {
        Name => 'NumIndexEntries',
        Format => 'int16u',
    },
    85 => {
        Name => 'ColorPalette',
        Writable => 0,
        Binary => 1,
    },
    86 => {
        Name => 'IPTCBitsPerSample',
        Format => 'int8u',
    },
    90 => {
        Name => 'SampleStructure',
        Format => 'int8u',
        PrintConv => {
            0 => 'OrthogonalConstangSampling',
            1 => 'Orthogonal4-2-2Sampling',
            2 => 'CompressionDependent',
        },
    },
    100 => {
        Name => 'ScanningDirection',
        Format => 'int8u',
        PrintConv => {
            0 => 'L-R, Top-Bottom',
            1 => 'R-L, Top-Bottom',
            2 => 'L-R, Bottom-Top',
            3 => 'R-L, Bottom-Top',
            4 => 'Top-Bottom, L-R',
            5 => 'Bottom-Top, L-R',
            6 => 'Top-Bottom, R-L',
            7 => 'Bottom-Top, R-L',
        },
    },
    102 => {
        Name => 'IPTCImageRotation',
        Format => 'int8u',
        PrintConv => {
            0 => 0,
            1 => 90,
            2 => 180,
            3 => 270,
        },
    },
    110 => {
        Name => 'DataCompressionMethod',
        Format => 'int32u',
    },
    120 => {
        Name => 'QuantizationMethod',
        Format => 'int8u',
        PrintConv => {
            0 => 'Linear Reflectance/Transmittance',
            1 => 'Linear Density',
            2 => 'IPTC Ref B',
            3 => 'Linear Dot Percent',
            4 => 'AP Domestic Analogue',
            5 => 'Compression Method Specific',
            6 => 'Color Space Specific',
            7 => 'Gamma Compensated',
        },
    },
    125 => {
        Name => 'EndPoints',
        Writable => 0,
        Binary => 1,
    },
    130 => {
        Name => 'ExcursionTolerance',
        Format => 'int8u',
        PrintConv => {
            0 => 'Not Allowed',
            1 => 'Allowed',
        },
    },
    135 => {
        Name => 'BitsPerComponent',
        Format => 'int8u',
    },
    140 => {
        Name => 'MaximumDensityRange',
        Format => 'int16u',
    },
    145 => {
        Name => 'GammaCompensatedValue',
        Format => 'int16u',
    },
);

# Record 7 -- Pre-object Data
%Image::ExifTool::IPTC::PreObjectData = (
    # (not actually writable, but used in BuildTagLookup to recognize IPTC tables)
    WRITE_PROC => \&WriteIPTC,
    10 => {
        Name => 'SizeMode',
        Format => 'int8u',
        PrintConv => {
            0 => 'Size Not Known',
            1 => 'Size Known',
        },
    },
    20 => {
        Name => 'MaxSubfileSize',
        Format => 'int32u',
    },
    90 => {
        Name => 'ObjectSizeAnnounced',
        Format => 'int32u',
    },
    95 => {
        Name => 'MaximumObjectSize',
        Format => 'int32u',
    },
);

# Record 8 -- ObjectData
%Image::ExifTool::IPTC::ObjectData = (
    WRITE_PROC => \&WriteIPTC,
    10 => {
        Name => 'SubFile',
        Flags => 'List',
        Binary => 1,
    },
);

# Record 9 -- PostObjectData
%Image::ExifTool::IPTC::PostObjectData = (
    WRITE_PROC => \&WriteIPTC,
    10 => {
        Name => 'ConfirmedObjectSize',
        Format => 'int32u',
    },
);


#------------------------------------------------------------------------------
# AutoLoad our writer routines when necessary
#
sub AUTOLOAD
{
    return Image::ExifTool::DoAutoLoad($AUTOLOAD, @_);
}

#------------------------------------------------------------------------------
# Print conversion for CodedCharacterSet
# Inputs: 0) value
sub PrintCodedCharset($)
{
    my $val = shift;
    return $iptcCharset{$val} if $iptcCharset{$val};
    $val =~ s/(.)/ $1/g;
    $val =~ s/ \x1b/, ESC/g;
    $val =~ s/^,? //;
    return $val;
}
        
#------------------------------------------------------------------------------
# Handle CodedCharacterSet
# Inputs: 0) ExifTool ref, 1) CodedCharacterSet value
# Returns: external character set if translation required (or 'bad' if unknown)
sub HandleCodedCharset($$)
{
    my ($exifTool, $val) = @_;
    my $xlat = $exifTool->Options('Charset');
    if ($iptcCharset{$val}) {
        # no need to translate if destination is the same
        undef $xlat if $xlat eq $iptcCharset{$val};
    } elsif ($val =~ /^\x1b\x25/) {
        # some unknown character set involked
        $xlat = 'bad';  # flag unsupported coding
    } else {
        # translate all other codes as Latin
        undef $xlat if $xlat eq 'Latin';
    }
    return $xlat;
}

#------------------------------------------------------------------------------
# Encode or decode coded string
# Inputs: 0) ExifTool ref, 1) value ptr, 2) destination charset ('Latin','UTF8' or 'bad')
#         3) flag set to decode (read) value from IPTC
# Updates value on return
sub TranslateCodedString($$$$)
{
    my ($exifTool, $valPtr, $xlatPtr, $read) = @_;
    my $escaped;
    if ($$xlatPtr eq 'bad') {
        $exifTool->Warn('Some IPTC characters not converted (unsupported CodedCharacterSet)');
        undef $$xlatPtr;
    } elsif ($$xlatPtr eq 'Latin' xor $read) {
        # don't yet support reading ISO 2022 shifted character sets
        if (not $read or $$valPtr !~ /[\x14\x15\x1b]/) {
            # convert from Latin to UTF-8
            my $val = Image::ExifTool::Latin2Unicode($$valPtr,'n');
            $$valPtr = Image::ExifTool::Unicode2UTF8($val,'n');
        } elsif (not $$exifTool{WarnShift2022}) {
            $exifTool->Warn('Some IPTC characters not converted (ISO 2022 shifting not supported)');
            $$exifTool{WarnShift2022} = 1;
        }
    } else {
        # convert from UTF-8 to Latin
        my $val = Image::ExifTool::UTF82Unicode($$valPtr,'n',$exifTool);
        $$valPtr = Image::ExifTool::Unicode2Latin($val,'n',$exifTool);
    }
}

#------------------------------------------------------------------------------
# get IPTC info
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
#         2) reference to tag table
# Returns: 1 on success, 0 otherwise
sub ProcessIPTC($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $pos = $$dirInfo{DirStart} || 0;
    my $dirLen = $$dirInfo{DirLen} || 0;
    my $dirEnd = $pos + $dirLen;
    my $verbose = $exifTool->Options('Verbose');
    my $success = 0;
    my (%listTags, $lastRec, $recordPtr, $recordName);

    # begin by assuming IPTC is Latin (so no translation if Charset is Latin)
    my $xlat = $exifTool->Options('Charset');
    undef $xlat if $xlat eq 'Latin';
    
    $verbose and $dirInfo and $exifTool->VerboseDir('IPTC', 0, $$dirInfo{DirLen});
    if ($tagTablePtr eq \%Image::ExifTool::IPTC::Main) {
        my $dirCount = ($exifTool->{DIR_COUNT}->{IPTC} || 0) + 1;
        $exifTool->{DIR_COUNT}->{IPTC} = $dirCount;
        $exifTool->{SET_GROUP1} = '+' . $dirCount if $dirCount > 1;
    }
    # quick check for improperly byte-swapped IPTC
    if ($dirLen >= 4 and substr($$dataPt, $pos, 1) ne "\x1c" and
                         substr($$dataPt, $pos + 3, 1) eq "\x1c")
    {
        $exifTool->Warn('IPTC data was improperly byte-swapped');
        my $newData = pack('N*', unpack('V*', substr($$dataPt, $pos, $dirLen) . "\0\0\0"));
        $dataPt = \$newData;
        $pos = 0;
        $dirEnd = $pos + $dirLen;
        # NOTE: MUST NOT access $dirInfo DataPt, DirStart or DataLen after this!
    }
    while ($pos + 5 <= $dirEnd) {
        my $buff = substr($$dataPt, $pos, 5);
        my ($id, $rec, $tag, $len) = unpack("CCCn", $buff);
        unless ($id == 0x1c) {
            unless ($id) {
                # scan the rest of the data an give warning unless all zeros
                # (iMatch pads the IPTC block with nulls for some reason)
                my $remaining = substr($$dataPt, $pos, $dirEnd - $pos);
                last unless $remaining =~ /[^\0]/;
            }
            $exifTool->Warn(sprintf('Bad IPTC data tag (marker 0x%x)',$id));
            last;
        }
        if (not defined $lastRec or $lastRec != $rec) {
            my $tableInfo = $tagTablePtr->{$rec};
            unless ($tableInfo) {
                $exifTool->Warn("Unrecognized IPTC record $rec, subsequent records ignored");
                last;   # stop now because we're probably reading garbage
            }
            my $tableName = $tableInfo->{SubDirectory}->{TagTable};
            unless ($tableName) {
                $exifTool->Warn("No table for IPTC record $rec!");
                last;   # this shouldn't happen
            }
            $recordName = $$tableInfo{Name};
            $recordPtr = Image::ExifTool::GetTagTable($tableName);
            $exifTool->VPrint(0,$$exifTool{INDENT},"-- $recordName record --\n");
            $lastRec = $rec;
        }
        $pos += 5;      # step to after field header
        # handle extended IPTC entry if necessary
        if ($len & 0x8000) {
            my $n = $len & 0x7fff; # get num bytes in length field
            if ($pos + $n > $dirEnd or $n > 8) {
                $exifTool->VPrint(0, "Invalid extended IPTC entry (tag $tag)\n");
                $success = 0;
                last;
            }
            # determine length (a big-endian, variable sized int)
            for ($len = 0; $n; ++$pos, --$n) {
                $len = $len * 256 + ord(substr($$dataPt, $pos, 1));
            }
        }
        if ($pos + $len > $dirEnd) {
            $exifTool->VPrint(0, "Invalid IPTC entry (tag $tag, len $len)\n");
            $success = 0;
            last;
        }
        my $val = substr($$dataPt, $pos, $len);

        # add tagInfo for all unknown tags:
        unless ($$recordPtr{$tag}) {
            # - no Format so format is auto-detected
            # - no Name so name is generated automatically with decimal tag number
            Image::ExifTool::AddTagToTable($recordPtr, $tag, { Unknown => 1 });
        }

        my $tagInfo = $exifTool->GetTagInfo($recordPtr, $tag);
        my $format;
        $format = $$tagInfo{Format} if $tagInfo;
        # use logic to determine format if not specified
        unless ($format) {
            $format = 'int' if $len <= 4 and $len != 3 and $val =~ /[\0-\x08]/;
        }
        if ($format) {
            if ($format =~ /^int/) {
                if ($len <= 8) {    # limit integer conversion to 8 bytes long
                    $val = 0;
                    my $i;
                    for ($i=0; $i<$len; ++$i) {
                        $val = $val * 256 + ord(substr($$dataPt, $pos+$i, 1));
                    }
                }
            } elsif ($format =~ /^string/) {
                if ($rec == 1) {
                    # handle CodedCharacterSet tag
                    $xlat = HandleCodedCharset($exifTool, $val) if $tag == 90;
                # translate characters if necessary and special characters exist
                } elsif ($xlat and $rec < 7 and $val =~ /[\x80-\xff]/) {
                    # translate to specified character set
                    TranslateCodedString($exifTool, \$val, \$xlat, 1);
                }
            } elsif ($format !~ /^digits/) {
                warn("Invalid IPTC format: $format");
            }
        }
        $verbose and $exifTool->VerboseInfo($tag, $tagInfo,
            Table   => $tagTablePtr,
            Value   => $val,
            DataPt  => $dataPt,
            DataPos => $$dirInfo{DataPos},
            Size    => $len,
            Start   => $pos,
            Extra   => ", $recordName record",
        );
        # prevent adding tags to list from another IPTC directory
        if ($tagInfo) {
            if ($$tagInfo{List}) {
                $exifTool->{NO_LIST} = 1 unless $listTags{$tagInfo};
                $listTags{$tagInfo} = 1;    # list the next one we see
            }
            $exifTool->FoundTag($tagInfo, $val);
        }
        delete $exifTool->{NO_LIST};
        $success = 1;

        $pos += $len;   # increment to next field
    }
    delete $exifTool->{SET_GROUP1};
    return $success;
}

1; # end


__END__

=head1 NAME

Image::ExifTool::IPTC - Read IPTC meta information

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
IPTC (International Press Telecommunications Council) meta information in
image files.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.iptc.org/IIM/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/IPTC Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
