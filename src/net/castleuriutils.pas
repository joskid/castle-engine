{
  Copyright 2007-2013 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ URI utilities. These extend standard FPC URIParser unit. }
unit CastleURIUtils;

interface

{ Extracts #anchor from URI. On input, URI contains full URI.
  On output, Anchor is removed from URI and saved in Anchor.
  If no #anchor existed, Anchor is set to ''. }
procedure URIExtractAnchor(var URI: string; out Anchor: string);

{ Replace all sequences like %xx with their actual 8-bit characters.

  The intention is that this is similar to PHP function with the same name.

  To account for badly encoded strings, invalid encoded URIs do not
  raise an error --- they are only reported to OnWarning.
  So you can simply ignore them, or write a warning about them for user.
  This is done because often you will use this with
  URIs provided by the user, read from some file etc., so you can't be sure
  whether they are correctly encoded, and raising error unconditionally
  is not OK. (Considering the number of bad HTML pages on WWW.)

  The cases of badly encoded strings are:

  @unorderedList(
    @item("%xx" sequence ends unexpectedly at the end of the string.
      That is, string ends with "%" or "%x". In this case we simply
      keep "%" or "%x" in resulting string.)

    @item("xx" in "%xx" sequence is not a valid hexadecimal number.
      In this case we also simply keep "%xx" in resulting string.)
  )
}
function RawURIDecode(const S: string): string;

{ Get protocol from given URI.

  This is very similar to how URIParser.ParseURI function detects the protocol,
  although not 100% compatible:

  @unorderedList(
    @item(We allow whitespace (including newline) before protocol name.

      This is useful, because some VRML/X3D files have the ECMAScript code
      inlined and there is sometimes whitespace before "ecmascript:" protocol.)

    @item(We never detect a single-letter protocol name.

      This is useful, because we do not use any single-letter protocol name,
      and it allows to detect Windows absolute filenames like
      @code(c:\blah.txt) as filenames. Otherwise, Windows absolute filenames
      could not be accepted by any of our routines that work with URLs
      (like the @link(Download) function),
      since they would be detected as URLs with unknown protocol "c".

      Our URIProtocol will answer that protocol is empty for @code(c:\blah.txt).
      Which means no protocol, so our engine will treat it as a filename.
      (In contrast with URIParser.ParseURI that would detect protocol called "c".)
      See doc/uri_filename.txt in sources for more comments about differentiating
      URI and filenames in our engine.)
  )
}
function URIProtocol(const URI: string): string;

{ Check does URI contain given Protocol.
  This is equivalent to checking URIProtocol(S) = Protocol, ignoring case,
  although may be a little faster. Given Protocol string cannot contain
  ":" character. }
function URIProtocolIs(const S: string; const Protocol: string; out Colon: Integer): boolean;

function URIDeleteProtocol(const S: string): string;

{ Return absolute URI, given base and relative URI.

  Base URI must be either an absolute (with protocol) URI, or only
  an absolute filename (in which case we'll convert it to file:// URI under
  the hood, if necessary). This is usually the URI of the containing file,
  for example an HTML file referencing the image, processed by AbsoluteURI.

  Relative URI may be a relative URI or an absolute URI.
  In the former case it is merged with Base.
  In the latter case it is simply returned. }
function CombineURI(const Base, Relative: string): string;

{ Make sure that the URI is absolute (always has a protocol).
  This function treats an URI without a protocol as a simple filename
  (absolute or relative to the current directory).
  This includes treating empty string as equivalent to current directory. }
function AbsoluteURI(const URI: string): string;

{ Convert URI (or filename) to a filename.
  This is an improved URIToFilename from URIParser.
  When URI is already a filename, this does a better job than URIToFilename,
  as it handles also Windows absolute filenames (see URIProtocol).
  Returns empty string in case of problems, for example when this is not
  a file URI.

  Just like URIParser.URIToFilename, this percent-decodes the parameter.
  For example, @code(%4d) in URI will turn into letter @code(M) in result. }
function URIToFilenameSafe(const URI: string): string;

{ Convert filename to URI.

  This is a fixed version of URIParser.FilenameToURI, that correctly
  percent-encodes the parameter, making it truly a reverse of
  URIToFilenameSafe. In FPC > 2.6.2 URIParser.FilenameToURI will also
  do this (after Michalis' patch, see
  http://svn.freepascal.org/cgi-bin/viewvc.cgi?view=revision&revision=24321 ). }
function FilenameToURISafe(const FileName: string): string;

{ Get MIME type for content of the URI @italic(without downloading the file).
  For local and remote files (file, http, and similar protocols)
  it guesses MIME type based on file extension.
  (Although we may add here detection of local file types by opening them
  and reading a header, in the future.)
  Only for data: URI scheme it actually reads the MIME type.

  Using this function is not adviced if you want to properly support
  MIME types returned by http server for network resources.
  For this, you have to download the file,
  as look at what MIME type the http server reports.
  The @link(Download) function returns such proper MimeType.
  This function only guesses without downloading.

  Returns empty string if MIME type is unknown. }
function URIMimeType(const URI: string): string;

{ Nice URI form to display.
  For now, this simply removes the long contents for data: URI,
  otherwise just returns the URI. }
function URIDisplayLong(const URI: string): string;

implementation

uses SysUtils, CastleStringUtils, CastleWarnings, CastleFilesUtils,
  URIParser, CastleUtils, CastleDataURI;

procedure URIExtractAnchor(var URI: string; out Anchor: string);
var
  HashPos: Integer;
begin
  HashPos := BackPos('#', URI);
  if HashPos <> 0 then
  begin
    Anchor := SEnding(URI, HashPos + 1);
    SetLength(URI, HashPos - 1);
  end;
end;

function RawURIDecode(const S: string): string;

  { Assume Position <= Length(S).
    Check is S[Positon] is a start of %xx sequence:
    - if not, exit false
    - if yes, but %xx is invalid, report OnWarning and exit false
    - if yes and %xx is valid, set DecodedChar and exit true }
  function ValidSequence(const S: string; Position: Integer;
    out DecodedChar: char): boolean;
  const
    ValidHexaChars = ['a'..'f', 'A'..'F', '0'..'9'];

    { Assume C is valid hex digit, return it's value (in 0..15 range). }
    function HexDigit(const C: char): Byte;
    begin
      if C in ['0'..'9'] then
        Result := Ord(C) - Ord('0') else
      if C in ['a'..'f'] then
        Result := 10 + Ord(C) - Ord('a') else
      if C in ['A'..'F'] then
        Result := 10 + Ord(C) - Ord('A');
    end;

  begin
    Result := S[Position] = '%';
    if Result then
    begin
      if Position + 2 > Length(S) then
      begin
        OnWarning(wtMajor, 'URI', Format(
          'URI "%s" incorrectly encoded, %%xx sequence ends unexpectedly', [S]));
        Exit(false);
      end;

      if (not (S[Position + 1] in ValidHexaChars)) or
         (not (S[Position + 2] in ValidHexaChars)) then
      begin
        OnWarning(wtMajor, 'URI', Format(
          'URI "%s" incorrectly encoded, %s if not a valid hexadecimal number',
          [S, S[Position + 1] + S[Position + 2]]));
        Exit(false);
      end;

      Byte(DecodedChar) := (HexDigit(S[Position + 1]) shl 4) or
                            HexDigit(S[Position + 2]);
    end;
  end;

var
  I, ResultI: Integer;
  DecodedChar: char;
begin
  { Allocate Result string at the beginning, to save time later for
    memory reallocations. We can do this, since we know that final
    Result is shorter or equal to S. }
  SetLength(Result, Length(S));

  ResultI := 1;
  I := 1;

  while I <= Length(S) do
  begin
    if ValidSequence(S, I, DecodedChar) then
    begin
      Result[ResultI] := DecodedChar;
      Inc(ResultI);
      Inc(I, 3);
    end else
    begin
      Result[ResultI] := S[I];
      Inc(ResultI);
      Inc(I);
    end;
  end;

  SetLength(Result, ResultI - 1);
end;

{ Detect protocol delimiting positions.
  If returns true, then for sure:
  - FirstCharacter < Colon
  - FirstCharacter >= 1
  - Colon > 1 }
function URIProtocolIndex(const S: string; out FirstCharacter, Colon: Integer): boolean;
const
  { These constants match URIParser algorithm, which in turn follows RFC. }
  ALPHA = ['A'..'Z', 'a'..'z'];
  DIGIT = ['0'..'9'];
  ProtoFirstChar = ALPHA;
  ProtoChar = ALPHA + DIGIT + ['+', '-', '.'];
var
  I: Integer;
begin
  Result := false;
  Colon := Pos(':', S);
  if Colon <> 0 then
  begin
    (* Skip beginning whitespace from protocol.
       This allows us to detect properly "ecmascript:" protocol in VRML/X3D:
      Script { url "
        ecmascript:..." }
    *)
    FirstCharacter := 1;
    while (FirstCharacter < Colon) and (S[FirstCharacter] in WhiteSpaces) do
      Inc(FirstCharacter);
    if FirstCharacter >= Colon then
      Exit;

    { Protocol name can only contain specific characters. }
    if not (S[FirstCharacter] in ProtoFirstChar) then
      Exit;
    for I := FirstCharacter + 1 to Colon - 1 do
      if not (S[I] in ProtoChar) then
        Exit;

    { Do not treat drive names in Windows filenames as protocol.
      To allow stable testing, do this on all platforms, even non-Windows.
      We do not use any single-letter protocol, so no harm. }
    Result := not ((FirstCharacter = 1) and (Colon = 2));
  end;
end;

function URIProtocol(const URI: string): string;
var
  FirstCharacter, Colon: Integer;
begin
  if URIProtocolIndex(URI, FirstCharacter, Colon) then
    Result := CopyPos(URI, FirstCharacter, Colon - 1) else
    Result := '';
end;

function URIProtocolIs(const S: string; const Protocol: string; out Colon: Integer): boolean;
var
  FirstCharacter, I: Integer;
begin
  Result := false;
  if URIProtocolIndex(S, FirstCharacter, Colon) and
     (Colon - FirstCharacter = Length(Protocol)) then
  begin
    for I := 1 to Length(Protocol) do
      if UpCase(Protocol[I]) <> UpCase(S[I - FirstCharacter + 1]) then
        Exit;
    Result := true;
  end;
end;

function URIDeleteProtocol(const S: string): string;
var
  FirstCharacter, Colon: Integer;
begin
  if URIProtocolIndex(S, FirstCharacter, Colon) then
    { Cut off also whitespace before FirstCharacter }
    Result := SEnding(S, Colon + 1) else
    Result := S;
end;

function CombineURI(const Base, Relative: string): string;
begin
  if not ResolveRelativeURI(AbsoluteURI(Base), Relative, Result) then
  begin
    { The only case when ResolveRelativeURI may fail is when neither argument
      contains a protocol. But we just used AbsoluteURI, which makes sure
      that AbsoluteURI(Base) has some protocol. }
    raise EInternalError.CreateFmt('Failed to resolve relative URI "%s" with base "%s"',
      [Relative, Base]);
  end;
end;

function AbsoluteURI(const URI: string): string;
begin
  if URIProtocol(URI) = '' then
    Result := FilenameToURISafe(ExpandFileName(URI)) else
    Result := URI;
end;

function URIToFilenameSafe(const URI: string): string;
var
  P: string;
begin
  { Use our URIProtocol instead of depending that URIToFilename will detect
    empty protocol case correctly. This allows to handle Windows absolute
    filenames like "c:\foo" as filenames. }
  P := URIProtocol(URI);
  if P = '' then
    Result := URI else
  if P = 'file' then
  begin
    if not URIToFilename(URI, Result) then Result := '';
  end else
    Result := '';
end;

function FilenameToURISafe(const FileName: string): string;

{ Code adjusted from FPC FilenameToURI (same license as our engine,
  so it's Ok to share code). Adjusted to call Escape on FileName.
  See http://bugs.freepascal.org/view.php?id=24324 : FPC FilenameToURI
  should be fixed in the future to follow this. }

const
  SubDelims = ['!', '$', '&', '''', '(', ')', '*', '+', ',', ';', '='];
  ALPHA = ['A'..'Z', 'a'..'z'];
  DIGIT = ['0'..'9'];
  Unreserved = ALPHA + DIGIT + ['-', '.', '_', '~'];
  ValidPathChars = Unreserved + SubDelims + ['@', ':', '/'];

  function Escape(const s: String; const Allowed: TSysCharSet): String;
  var
    i, L: Integer;
    P: PChar;
  begin
    L := Length(s);
    for i := 1 to Length(s) do
      if not (s[i] in Allowed) then Inc(L,2);
    if L = Length(s) then
    begin
      Result := s;
      Exit;
    end;

    SetLength(Result, L);
    P := @Result[1];
    for i := 1 to Length(s) do
    begin
      if not (s[i] in Allowed) then
      begin
        P^ := '%'; Inc(P);
        StrFmt(P, '%.2x', [ord(s[i])]); Inc(P);
      end
      else
        P^ := s[i];
      Inc(P);
    end;
  end;


var
  I: Integer;
  IsAbsFilename: Boolean;
  FilenamePart: string;
begin
  IsAbsFilename := ((Filename <> '') and (Filename[1] = PathDelim)) or
    ((Length(Filename) > 2) and (Filename[1] in ['A'..'Z', 'a'..'z']) and (Filename[2] = ':'));

  Result := 'file:';
  if IsAbsFilename then
  begin
    if Filename[1] <> PathDelim then
      Result := Result + '///'
    else
      Result := Result + '//';
  end;

  FilenamePart := Filename;
  { unreachable code warning is ok here }
  {$warnings off}
  if PathDelim <> '/' then
  begin
    I := Pos(PathDelim, FilenamePart);
    while I <> 0 do
    begin
      FilenamePart[I] := '/';
      I := Pos(PathDelim, FilenamePart);
    end;
  end;
  {$warnings on}
  FilenamePart := Escape(FilenamePart, ValidPathChars);

  Result := Result + FilenamePart;
end;

function URIMimeType(const URI: string): string;

  function ExtToMimeType(Ext, ExtExt: string): string;
  begin
    Ext := LowerCase(Ext);
    ExtExt := LowerCase(ExtExt);

    { This list is based on
      http://svn.freepascal.org/cgi-bin/viewvc.cgi/trunk/lcl/interfaces/customdrawn/customdrawnobject_android.inc?root=lazarus&view=co&content-type=text%2Fplain
      (license is LGPL with static linking exception, just like our engine).
      See also various resources linked from
      "Function to get the mimetype from a file extension" thread on Lazarus
      mailing list:
      http://comments.gmane.org/gmane.comp.ide.lazarus.general/62738

      We somewhat cleaned it up (e.g. "postscript" and "mpeg" lowercase),
      fixed categorization, and fixed/added many types looking at
      /etc/mime.types and
      /usr/share/mime/packages/freedesktop.org.xml on Debian.

      For description of MIME content types see also
      https://en.wikipedia.org/wiki/Internet_media_type
      http://en.wikipedia.org/wiki/MIME
      http://tools.ietf.org/html/rfc4288 }

    // 3D models (see also view3dscene MIME specification in view3dscene/desktop/view3dscene.xml)
    if Ext    = '.wrl'    then Result := 'model/vrml' else
    if Ext    = '.wrz'    then Result := 'model/vrml' else
    if ExtExt = '.wrl.gz' then Result := 'model/vrml' else
    if Ext    = '.x3dv'    then Result := 'model/x3d+vrml' else
    if Ext    = '.x3dvz'   then Result := 'model/x3d+vrml' else
    if ExtExt = '.x3dv.gz' then Result := 'model/x3d+vrml' else
    if Ext    = '.x3d'    then Result := 'model/x3d+xml' else
    if Ext    = '.x3dz'   then Result := 'model/x3d+xml' else
    if ExtExt = '.x3d.gz' then Result := 'model/x3d+xml' else
    if Ext    = '.x3db'    then Result := 'model/x3d+binary' else
    if ExtExt = '.x3db.gz' then Result := 'model/x3d+binary' else
    if Ext = '.dae' then Result := 'model/vnd.collada+xml' else
    { See http://en.wikipedia.org/wiki/.3ds about 3ds mime type.
      application/x-3ds is better (3DS is hardly an "image"),
      but Debian /usr/share/mime/packages/freedesktop.org.xml also uses
      image/x-3ds, so I guess image/x-3ds is more popular. }
    if Ext = '.3ds' then Result := 'image/x-3ds' else
    if Ext = '.max' then Result := 'image/x-3ds' else
    if Ext = '.iv' then Result := 'object/x-inventor' else
    if Ext = '.md3' then Result := 'application/x-md3' else
    if Ext = '.obj' then Result := 'application/x-wavefront-obj' else
    if Ext = '.geo' then Result := 'application/x-geo' else
    if Ext = '.kanim' then Result := 'application/x-kanim' else
    // Images
    if Ext = '.png' then Result := 'image/png' else
    if Ext = '.jpg' then Result := 'image/jpeg' else
    if Ext = '.jpeg' then Result := 'image/jpeg' else
    if Ext = '.svg' then Result := 'image/svg+xml' else
    if Ext = '.xpm' then Result := 'image/x-xpixmap' else
    if Ext = '.gif' then Result := 'image/gif' else
    if Ext = '.tiff' then Result := 'image/tiff' else
    if Ext = '.tif' then Result := 'image/tiff' else
    if Ext = '.ico' then Result := 'image/x-icon' else
    if Ext = '.icns' then Result := 'image/icns' else
    if Ext = '.ppm' then Result := 'image/x-portable-pixmap' else
    if Ext = '.bmp' then Result := 'image/bmp' else
    // HTML
    if Ext = '.htm' then Result := 'text/html' else
    if Ext = '.html' then Result := 'text/html' else
    if Ext = '.shtml' then Result := 'text/html' else
    // Plain text
    if Ext = '.txt' then Result := 'text/plain' else
    if Ext = '.pas' then Result := 'text/plain' else
    if Ext = '.pp' then Result := 'text/plain' else
    if Ext = '.inc' then Result := 'text/plain' else
    if Ext = '.c' then Result := 'text/plain' else
    if Ext = '.cpp' then Result := 'text/plain' else
    if Ext = '.java' then Result := 'text/plain' else
    if Ext = '.log' then Result := 'text/plain'  else
    // Videos
    if Ext = '.mp4' then Result := 'video/mp4' else
    if Ext = '.avi' then Result := 'video/x-msvideo' else
    if Ext = '.mpeg' then Result := 'video/mpeg' else
    if Ext = '.mpg' then Result := 'video/mpeg' else
    if Ext = '.mov' then Result := 'video/quicktime' else
    // Sounds
    if Ext = '.mp3' then Result := 'audio/mpeg' else
    if Ext = '.ogg' then Result := 'audio/ogg' else
    if Ext = '.wav' then Result := 'audio/x-wav' else
    if Ext = '.mid' then Result := 'audio/midi' else
    if Ext = '.midi' then Result := 'audio/midi' else
    if Ext = '.au' then Result := 'audio/basic' else
    if Ext = '.snd' then Result := 'audio/basic' else
    // Documents
    if Ext = '.rtf' then Result := 'text/rtf' else
    if Ext = '.eps' then Result := 'application/postscript' else
    if Ext = '.ps' then Result := 'application/postscript' else
    if Ext = '.pdf' then Result := 'application/pdf' else
    // Documents - old MS Office
    if Ext = '.xls' then Result := 'application/vnd.ms-excel' else
    if Ext = '.doc' then Result := 'application/msword' else
    if Ext = '.ppt' then Result := 'application/vnd.ms-powerpoint' else
    // Documents - open standards
    if Ext = '.odt' then Result := 'application/vnd.oasis.opendocument.text' else
    if Ext = '.ods' then Result := 'application/vnd.oasis.opendocument.spreadsheet' else
    if Ext = '.odp' then Result := 'application/vnd.oasis.opendocument.presentation' else
    if Ext = '.odg' then Result := 'application/vnd.oasis.opendocument.graphics' else
    if Ext = '.odc' then Result := 'application/vnd.oasis.opendocument.chart' else
    if Ext = '.odf' then Result := 'application/vnd.oasis.opendocument.formula' else
    if Ext = '.odi' then Result := 'application/vnd.oasis.opendocument.image' else
    // Documents - new MS Office
    if Ext = '.xlsx' then Result := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' else
    if Ext = '.pptx' then Result := 'application/vnd.openxmlformats-officedocument.presentationml.presentation' else
    if Ext = '.docx' then Result := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' else
    // Compressed archives
    if Ext = '.zip' then Result := 'application/zip' else
    if Ext = '.tar' then Result := 'application/x-tar' else
    // Various
    if Ext = '.xml' then Result := 'application/xml' else
    if Ext = '.swf' then Result := 'application/x-shockwave-flash' else
      Result := '';
  end;

var
  P: string;
  DataURI: TDataURI;
begin
  Result := '';

  P := LowerCase(URIProtocol(URI));

  if P = 'data' then
  begin
    DataURI := TDataURI.Create;
    try
      DataURI.URI := URI;
      if DataURI.Valid then Result := DataURI.MimeType;
    finally FreeAndNil(DataURI) end;
  end else

  if (P = '') or
     (P = 'file') or
     (P = 'http') or
     (P = 'ftp') or
     (P = 'https') then
    { We're consciously using here ExtractFileExt and ExtractFileDoubleExt on URIs,
      although they should be used for filenames. }
    Result := ExtToMimeType(ExtractFileExt(URI), ExtractFileDoubleExt(URI));

end;

function URIDisplayLong(const URI: string): string;
var
  DataURI: TDataURI;
begin
  Result := URI;

  if TDataURI.IsDataURI(URI) then
  begin
    DataURI := TDataURI.Create;
    try
      DataURI.URI := URI;
      if DataURI.Valid then Result := DataURI.URIPrefix + ',...';
    finally FreeAndNil(DataURI) end;
  end;
end;

end.