{ @abstract(provides all the parsing functionality of pasdoc)
  @author(Ralf Junker (delphi@zeitungsjunge.de))
  @author(Marco Schmidt (marcoschmidt@geocities.com))
  @author(Johannes Berg <johannes@sipsolutions.de>)
  @author(Michalis Kamburelis)
  @author(Hans-Peter Diettrich <DrDiettrich1@aol.com>)
  @cvs($Date$)

  Parsing implements most of the functionality of the pasdoc program.

  It provides the @link(TParser) object, which scans the command line parameters
  for file names and switches and then starts collecting information from those
  files, issueing warnings to standard out if necessary. }

unit PasDoc_Parser;

{$I pasdoc_defines.inc}

interface

uses
  Classes,
  PasDoc_Types,
  PasDoc_Items,
  PasDoc_Scanner,
  PasDoc_Tokenizer,
  PasDoc_StringVector;


const
//Descriptive comment markers
  cmNoRem = #0;
  cmIgnore = '-';
  cmFwd = '>';
  cmBack = '<';
  cmBlock = '[';
  cmEnd = ']';
  cmMarkers = [cmIgnore, cmFwd, cmBack, cmBlock, cmEnd];

type
{$IFDEF old}
  // @name stores a series of @link(TRawDescriptionInfo TRawDescriptionInfos).
  // It is modelled after TStringList but has only the minimum number
  // of methods required for use in PasDoc.
  TRawDescriptionInfoList = class(TObject)
  private
    // @name holds the @link(TRawDescriptionInfo TRawDescriptionInfos) in @classname
    FItems: array of TRawDescriptionInfo;
    // @name holds the number of items currently stored in @classname.
    // @seealso(Count).
    FCount: integer;
    // @name is the read specifier for @link(Items)
    function GetItems(Index: integer): TRawDescriptionInfo;
    // @name expands the capacity of @link(FItems).
    procedure Grow;
  public
    // @name adds a new @link(TRawDescriptionInfo) to @classname.
    function Append(Comment: TRawDescriptionInfo): integer;
    // @name is the number of @link(TRawDescriptionInfo TRawDescriptionInfos) in
    // @classname.
    property Count: integer read FCount;
    Constructor Create;
    // @name provides read access to the
    // @link(TRawDescriptionInfo TRawDescriptionInfos) in @classname.
    property Items[Index: integer]: TRawDescriptionInfo read GetItems; default;
  end;
{$ELSE}
{$ENDIF}

//dummy class, for writeable TToken.EndPosition
  TCToken = class(TToken)
  protected
    property EndPos: TTextStreamPos read FEndPosition write FEndPosition;
  end;

  { Parser class that will process a complete unit file and all of its
    include files, regarding directives.
    When creating this object constructor @link(Create) takes as an argument
    an input stream and a list of directives.
    Parsing work is done by calling @link(ParseUnitOrProgram) method.
    If no errors appear, should return a @link(TPasUnit) object with
    all information on the unit. Else exception is raised.

    Things that parser inits in items it returns:

    @unorderedList(
      @item(Of every TPasItem :
        Name, RawDescription, Visibility, IsDeprecated, IsPlatformSpecific,
        IsLibrarySpecific, FullDeclararation (note: for now not all items
        get sensible FullDeclararation, but the intention is to improve this
        over time; see @link(TPasItem.FullDeclaration) to know where
        FullDeclararation is available now).

        Note to IsDeprecated: parser inits it basing on hint directive
        "deprecated" presence in source file; it doesn't handle the fact
        that @@deprecated tag may be specified inside RawDescription.

        Note to RawDescription: parser inits them from user's comments
        that preceded given item in source file.
        It doesn't handle the fact that @@member and @@value tags
        may also assign RawDescription for some item.)

      @item Of TPasCio: Ancestors, Fields, Methods, Properties, MyType.

      @item Of TPasEnum: Members, FullDeclararation.

      @item Of TPasMethod: What.

      @item Of TPasVarConst: FullDeclaration.

      @item(Of TPasProperty: IndexDecl, FullDeclaration.
        PropType (only if was specified in property declaration).
        It was intended that parser will also set Default,
        NoDefault, StoredId, DefaultId, Reader, Writer attributes,
        but it's still not implemented.)

      @item(Of TPasUnit; UsesUnits, Types, Variables, CIOs, Constants,
        FuncsProcs.)
    )

    It doesn't init other values.
    E.g. AbstractDescription or DetailedDescription of TPasItem
    should be inited while expanding this item's tags.
    E.g. SourceFileDateTime and SourceFileName of TPasUnit must
    be set by other means. }
  TParser = class
  private
    FImplicitVisibility: TImplicitVisibility;

    { The underlying scanner object. }
    Scanner: TScanner;

    FOnMessage: TPasDocMessageEvent;
    FVerbosity: Cardinal;

    procedure DoError(const AMessage: string;
      const AArguments: array of const);
    procedure DoMessage(const AVerbosity: Cardinal; const MessageType:
      TPasDocMessageType; const AMessage: string; const AArguments: array of const);

  protected
  //Token + whitespace recorder
    Token, Peeked: TToken;
    Recorder: string;
    PrevRecordSize: integer;

    { Reads tokens and throws them away as long as they are either whitespace
      or comments.

      Sets WhitespaceCollector to all the whitespace that was skipped.
      (Does @italic(not) append them to WhitespaceCollector,
      it @italic(sets) WhitespaceCollector to them, deleting previous
      WhitespaceCollector value.)

      Comments are collected to [Is]LastCommentXxx properties, so that you can
      use GetLastComment.

      Returns non-white token that was found.
      This token is equal to @code(Scanner.PeekToken).
      Note that this token was @italic(peeked)
      from the stream, i.e. the caller is still responsible for doing
      @code(Scanner.ConsumeToken).
      Calling this method twice in a row will return the same thing.

      Always returns something non-nil (will raise exception in case
      of problems, e.g. when stream ended). }
    function PeekNextToken: TTokenType;
  //Make next token current, record it.
    function  GetNextToken: TTokenType;
  //Makes previously peeked token current and records it.
    procedure ConsumeToken;
  //Return recorded tokens. Optionally strip last token.
  //Recorder is cleared.
    function  Recorded(fStripLast: boolean = False): string;
  //Get next token and verify that it has the expected TTokenType.
    procedure Expect(tt: TTokenType);
  //Get next token, if it has the expected type.
    function  Skip(tt: TTokenType): boolean; overload;
  //Get next token, if it is the expected directive.
    function  Skip(dir: TStandardDirective): boolean; overload;

    { Checks if T.MyType is ATokenType, if not calls DoError
      with appropriate error mesg. }
    procedure CheckToken(T: TToken; ATokenType: TTokenType);

  protected
    FCommentMarkers: TStringList;
    FMarkersOptional: boolean;
  //Token chain
    Pending, BlockComment: TToken;
    Identifier: TToken;

    { These are the items that the next "back-comment"
      (the comment starting with "<", see
      [http://pasdoc.sipsolutions.net/WhereToPlaceComments]
      section "Placing comments after the item") will apply to. }
    CurScope: TPasScope;
    ScopeStack: TList;
    procedure OpenScope(AScope: TPasScope);
    function  CloseScope: TPasScope;

  (* New comment model:
    Comments and Name tokens are kept in a token chain.
    C-style comments are collected into one (the first) token,
      as long as all comments come from the same stream.
    New comments are chained by PeekNextToken,
      unless they are back-comments to the current item (empty token list).
    CreateItem will remove (add or discard) all pending comments,
      and the chained Name token.
      Pending comments from different streams are discarded.
  *)
  //apply comment to the (just created) item.
    procedure ApplyComments(item: TPasItem);
  //try append description, return succ/fail
    function  AddDescription(var t: TToken; item: TPasItem = nil;
      fDestroy: boolean = True): boolean;
  //not yet...
    //function  ShiftComments: boolean;
    procedure CancelComments;
  //put new comment into the queue
    procedure PushComment(var C: TToken);

  (* parse qualified identifier, get first ident if fGet.  *)
    function  QualID(fGet: boolean; fOperator: boolean = False): TToken;

    { Parses a constructor, a destructor, a function or a procedure
      or an operator (for FPC).
      Resulting @link(TPasMethod) item will be returned in M.

      ClassKeywordString contains the keyword 'class'
      in the exact spelling as it was found in input,
      for class methods. Else it contains ''.

      MethodTypeString contains the keyword 'constructor', 'destructor',
      'function' or 'procedure' or standard directive 'operator'
      in the exact spelling as it was found in input.
      You can specify MethodTypeString = '', this way you avoid including
      such keyword at the beginning of returned M.FullDeclaration.

      MethodType is used for the What field of the resulting TPasMethod.
      This should correspond to MethodTypeString.

      D may contain a description or nil. }
    function  ParseCDFP(
      fClass: boolean;  //<???
      MethodType: TTokenType;
      Ident: TToken): TPasMethod;

    { Parses a class, an interface or an object.
      U is the unit this item will be added to on success.
      N is the name of this item.
      CIOType describes if item is class, interface or object.
      D may contain a description or nil. }
      function ParseCIO(Ident: TToken; //const CioName: string;
        CIOType: TTokenType;
        const IsInRecordCase: boolean): TPasCio;

    //procedure ParseRecordCase(const R: TPasCio; const SubCase: boolean);
    procedure ParseRecordCase(const SubCase: boolean);
    procedure ParseConstant;  //(const U: TPasUnit);
    procedure ParseInterfaceSection(const U: TPasUnit);
  //properties for units or CIOs - deserves a common base class?
    //function  ParseProperty(U: TPasScope; Visibility: TVisibility): TPasProperty;
    function  ParseProperty: TPasProperty;
    procedure ParseType;  //(const U: TPasUnit);

    { This assumes that you just read left parenthesis starting
      an enumerated type. It finishes parsing of TPasEnum,
      returning it. }
    function  ParseEnum: TPasEnum;
    //function  ParseEnum(const Name: string): TPasEnum;

    procedure ParseUses(const U: TPasUnit);

    { This parses the sequence of identifiers separated by commas
      and ended by symbol FinalSymbol. More specifically in EBNF it parses
        TOK_IDENTIFIER (SYM_COMMA TOK_IDENTIFIER)+ FinalSymbol
      FinalSymbol must be something else than SYM_COMMA.
      After executing this, next token (returned by GetNextToken and PeekNextToken)
      will point to the next token right after FinalSymbol.
      All found identifiers will be appended to Names.

      If RawDescriptions <> nil then this will also get
      all comments documenting the identifiers in Names
      (it will append the same number of items to
      RawDescriptions as it appended to Names).
      The strategy how comments are assigned to item in this case is
      described on [http://pasdoc.sipsolutions.net/WhereToPlaceComments]
      (see section "Multiple fields/variables in one declaration"). }

  (* Create an item in CurScope, using the current Token information.
    Make the new item the target for back-comments.
  *)
    function CreateItem(AClass: TPasItemClass; tt: TTokenType; Ident: TToken): TPasItem;
  (* Parse an identifier list, create an item for every identifier.
    Return the first of these items, to e.g. limit the update of the shared
      FullDeclaration.
    Uses: in var declarations, argument lists, CIO fields
      Typically AClass is TPasFieldVariable, tt is KEY_VAR.
  *)
    function ParseVarList: TPasItem;
    //function ParseIdentList(AClass: TPasItemClass; tt: TTokenType): TPasItem;

    { Parse variables or fields clause
      ("one clause" is something like
        NAME1, NAME2, ... : TYPE;
      i.e. a list of variables/fields sharing one type declaration.)

      @param(inUnit: also parse FPC modifiers?)
    }
    procedure ParseVariables(inUnit: boolean);

    { Read all tokens until you find a semicolon at brace-level 0 and
      end-level (between "record" and "end" keywords) also 0.

      Alternatively, also stops before reading "end" without beginning
      "record" (so it can handle some cases where declaration doesn't end
      with semicolon).

      Alternatively, only if IsInRecordCase, also stops before reading
      ')' without matching '('. That's because fields' declarations
      inside record case may be terminated by just ')' indicating
      that this case clause terminates, without a semicolon.

      If you pass Item <> nil then all read data will be
      appended to Item.FullDeclaration. Also Item.IsLibrarySpecific,
      Item.IsPlatformSpecific and Item.IsDeprecated will be set to true
      if appropriate hint directive will occur in source file. }
  {$IFDEF old}
    procedure SkipDeclaration(const Item: TPasItem; IsInRecordCase: boolean);
  {$ELSE}
  //changed signature!
    procedure SkipDeclaration(fSkipNext: boolean; CurItem: TPasItem);
  {$ENDIF}

    procedure SetCommentMarkers(const Value: TStringList);

    { Skips all whitespace and comments and while it sees some hint directive
      (platform, library, deprecated) it consumes it, sets appropriate
      property of Item (IsPlatformSpecific, IsLibrarySpecific or IsDeprecated)
      to true and goes further.

      Stops when PeekNextToken returns some non-whitespace non-comment
      non-hint-directive token. }
    procedure ParseHintDirectives(Item: TPasItem);

    procedure ParseUnit(U: TPasUnit);
    procedure ParseProgram(U: TPasUnit);
    procedure ParseProgramOrLibraryUses(U: TPasUnit);
    procedure ParseLibrary(U: TPasUnit);
  public
  (* New comment handling, if True:
    The first character of an comment can be one of:
    "-" cmIgnore - the comment is ignored.
    "<" cmBack - the comment is a back-comment, on the preceding item.
    ">" cmFwd - the comment is a forward comment, on the following item.
    "[" cmBegin - starts an block comment, applied to all following items, until
    "]" cmEnd - the block is terminated.
    "*" and "/" invert the direction of the comment.
    These marker characters are removed from the description text.

    Unmarked comments are ignored, unless markers are optional. In this case
    the direction of the comment is determined by the comment style:
    Pascal comments become forward comments,
    C-style comments become back-comments.
    The "*" and "/" markers invert that direction.
    This is only a compatibility hack, better use ">" and "<" markers instead.
  *)
    SingleCharMarkers: boolean;

    { Create a parser, initialize the scanner with input stream S.
      All strings in SD are defined compiler directives. }
    constructor Create(
      const InputStream: TStream;
      const Directives: TStringVector;
      const IncludeFilePaths: TStringVector;
      const OnMessageEvent: TPasDocMessageEvent;
      const VerbosityLevel: Cardinal;
      const AStreamName, AStreamPath: string;
      const AHandleMacros: boolean);

    { Release all dynamically allocated memory. }
    destructor Destroy; override;

    { This does the real parsing work, creating U unit and parsing
      InputStream and filling all U properties. }
    procedure ParseUnitOrProgram(var U: TPasUnit);

    property OnMessage: TPasDocMessageEvent read FOnMessage write FOnMessage;
    property CommentMarkers: TStringList read FCommentMarkers write SetCommentMarkers;
    property MarkersOptional: boolean read fMarkersOptional write fMarkersOptional;
  {$IFDEF old}
  //ShowVisibilities should be global, reachable from the items!
    property ShowVisibilities: TVisibilities
      read FShowVisibilities write FShowVisibilities;
  {$ELSE}
  //if this is ever needed... (ShowVisibilities was moved into PasDoc_items)
    class function ShowVisibilities: TVisibilities;
  {$ENDIF}

    { See command-line option @--implicit-visibility documentation at
      [http://pasdoc.sipsolutions.net/ImplicitVisibilityOption] }
    property ImplicitVisibility: TImplicitVisibility
      read FImplicitVisibility write FImplicitVisibility;
  end;

implementation

uses
  SysUtils,
  PasDoc_Utils;

{$IFDEF old}

{ TRawDescriptionInfoList --------------------------------------------------------------- }

function TRawDescriptionInfoList.GetItems(Index: integer): TRawDescriptionInfo;
begin
  { FItems is a dynarray, so compiler will automatically
    add appropriate range checks here in $R+ mode.
    So no need to explicitly check Index for validity here. }
  Result := FItems[Index];
end;

procedure TRawDescriptionInfoList.Grow;
var
  Delta: integer;
begin
  if Length(FItems) < 16 then begin
    Delta := 4;
  end
  else begin
    Delta := Length(FItems) div 4;
  end;
  SetLength(FItems, Length(FItems) + Delta);
end;

function TRawDescriptionInfoList.Append(Comment: TRawDescriptionInfo): integer;
begin
  if Length(FItems) = Count then Grow;
  FItems[Count] := Comment;
  result := Count;
  Inc(FCount);
end;

constructor TRawDescriptionInfoList.Create;
begin
  inherited;
  SetLength(FItems, 4);
  FCount := 0;
end;
{$ELSE}
{$ENDIF}

{ ---------------------------------------------------------------------------- }
{ TParser }
{ ---------------------------------------------------------------------------- }

constructor TParser.Create(
  const InputStream: TStream;
  const Directives: TStringVector;
  const IncludeFilePaths: TStringVector;
  const OnMessageEvent: TPasDocMessageEvent;
  const VerbosityLevel: Cardinal;
  const AStreamName, AStreamPath: string;
  const AHandleMacros: boolean);
begin
  inherited Create;
  FOnMessage := OnMessageEvent;
  FVerbosity := VerbosityLevel;

  Scanner := TScanner.Create(InputStream, OnMessageEvent,
    VerbosityLevel, AStreamName, AStreamPath, AHandleMacros);
  Scanner.AddSymbols(Directives);
  Scanner.IncludeFilePaths := IncludeFilePaths;
  FCommentMarkers := TStringlist.Create;
  //ItemsForNextBackComment := TPasItems.Create(false);
  ScopeStack := TList.Create;
end;

{ ---------------------------------------------------------------------------- }

destructor TParser.Destroy;
begin
  FCommentMarkers.Free;
  Scanner.Free;
  //ItemsForNextBackComment.Free;
  ScopeStack.Free;
  Peeked.Free;
  Token.Free;
  Identifier.Free;
  BlockComment.Free;
  CancelComments;
  inherited;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.DoError(const AMessage: string;
  const AArguments: array of const);
begin
  raise EPasDoc.Create(Scanner.GetStreamInfo + ': ' + AMessage, AArguments, 1);
end;

procedure TParser.DoMessage(const AVerbosity: Cardinal; const MessageType:
  TPasDocMessageType; const AMessage: string; const AArguments: array of const);
begin
  if (AVerbosity <= FVerbosity) and Assigned(FOnMessage) then
    FOnMessage(MessageType, Format(AMessage, AArguments), AVerbosity);
end;

{ ---------------------------------------------------------------------------- }

function TParser.PeekNextToken: TTokenType;
//type  ePeekState = (psWait, psCollect, psGotRem, psDone);
var
  T: TToken;
  C: TToken;

  { The comment is intended to be a "documentation comment",
    i.e. we intend to put it inside output documentation.
    So comment markers, if present, are removed from the beginning of the data.
    Also, if comment markers were required but were not present,
    then CommentInfo.Content is an empty string.

    Also back-comment marker, the '<', is removed, if exists,
    and BackComment is set to @true. Otherwise BackComment is @false. }
  procedure ExtractDocComment;
  const
    BackCommentMarker = '<';
  var
    i: integer;
    Marker: string;
    WasMarker: boolean;
    cm: char;
  begin
    if SingleCharMarkers then begin
      cm := C.data[1];
      if cm in cmMarkers then
        Delete(C.Data, 1, 1)
      else begin
        WasMarker := cm in ['/', '*'];
        if WasMarker then
          Delete(C.Data, 1, 1);
        if (C.MyType = TOK_COMMENT_CSTYLE) = WasMarker then
        // ( * or / / /
          cm := cmFwd
        else  // ( ** or / /
          cm := cmBack;
      end;
    end else begin
      WasMarker := false;
      cm := cmFwd;  //default

      for i := 0 to CommentMarkers.Count - 1 do begin
        Marker := CommentMarkers[i];
        if IsPrefix(Marker, c.Data) then begin
          Delete(C.Data, 1, Length(Marker));
          WasMarker := true;
          Break;
        end;
      end;

      if (not MarkersOptional) and (not WasMarker) then
        cm := cmIgnore
      else if SCharIs(c.Data, 1, BackCommentMarker) then begin
        cm := cmBack;
        Delete(C.Data, 1, Length(BackCommentMarker));
      end;
    end;
  //now dispatch
    if cm = cmIgnore then
      FreeAndNil(C)
    else begin
      c.Mark := cm;
      PushComment(C);
    end;
  end;

  { Collect multiple C-style comments.
    Dispatch non-C-style comments immediately.
    Also flush stream/style mismatched comments.
  }
  procedure Collect(fCstyle: boolean);
  begin
    if (C <> nil) then begin
    //check for extension of an pending C style comment
      if (c.StreamName <> t.StreamName) or not fCstyle then begin
      //cannot append: different stream or comment style
        ExtractDocComment;  //old comment
        assert(C = nil, 'comment not dispatched');
      end;
    end;
    if C = nil then begin
    //first comment
    //ignore if empty? clear pending comments?
      if t.CommentContent <= ' ' then begin
        CancelComments;
        FreeAndNil(t);
        exit;
      end;
    {$IFDEF old}
      NextCommentInfo.Content := T.CommentContent;
      NextCommentInfo.StreamName := T.StreamName;
      NextCommentInfo.BeginPosition := T.BeginPosition;
      NextCommentInfo.EndPosition := T.EndPosition;
    {$ELSE}
      TToken(C) := T;
      T := nil;
    {$ENDIF}
      if not fCstyle then
        ExtractDocComment; //finish comment
  //else a C-style comment is waiting for continuation
    //end else if fCstyle and (t.StreamName = c.StreamName) then begin
    end else begin  //all conditions checked above!
    //append to preceding comment
      C.CommentContent := C.CommentContent + LineEnding + T.CommentContent;
      TCToken(c).EndPos := t.EndPosition;
      FreeAndNil(T);
    end;
  end;

begin
  if Peeked <> nil then begin
    Result := Peeked.MyType;
    exit;
  end;
//peek next
  C := nil; //NextCommentInfo.BeginPosition := -1;  //mark no rem
  PrevRecordSize := Length(Recorder); //allow to strip last token added
  repeat  //while state < psGotRem do begin
    t := Scanner.GetToken;
    case t.MyType of
    TOK_COMMENT_PAS, TOK_COMMENT_EXT:
      Collect(False);
    TOK_COMMENT_CSTYLE:
      Collect(True);
    TOK_WHITESPACE:
      begin
        if C = nil then //ignore between comments?
          Recorder := Recorder + ' '; //t.Data; - compress FullDeclaration
        FreeAndNil(T);
      end;
    else //case
      break;  //don't consume!
    end;
  until assigned(T); //collect comments
//did we get an comment?
  if assigned(C) then
    ExtractDocComment;
  Peeked := t;
  Result := t.MyType;
end;

procedure TParser.CancelComments;
var
  c: TToken;
begin
//kill all comments
  while Pending <> nil do begin
    c := Pending;
    Pending := c.Next;
    c.Free;
  end;
end;

procedure TParser.PushComment(var C: TToken);

  procedure AppendIt;
  var
    t: TToken;
  begin
    t := Pending;
    if t = nil then
      Pending := c
    else begin
      while t.Next <> nil do
        t := t.Next;
    //link token here
      t.Next := c;
    end;
    c := nil;
  end;

begin
  assert(assigned(c), 'cannot push Nil comment');
  case c.Mark of
  cmNoRem,  //???
  cmIgnore: FreeAndNil(C);
  cmBlock:
    begin
      BlockComment.Free;
      BlockComment := c;
    end;
  cmEnd:  FreeAndNil(BlockComment);
  cmBack: //try apply immediately
    if not AddDescription(C) then
      AppendIt;
  else  //any (forward) comment
    AppendIt;
  end;
end;

function TParser.AddDescription(var t: TToken; item: TPasItem; fDestroy: boolean): boolean;
var
  p: PRawDescriptionInfo;
begin
  Result := False; //in case of any errors
//check item
  if item = nil then begin
    if CurScope.Members.Count <= 0 then
      exit; //not item for comment
    item := CurScope.Members.LastItem
  end;
//check for tentative item?
  if assigned(Identifier)
  and (Identifier.BeginPosition > item.NamePosition)
  and (Identifier.BeginPosition < t.BeginPosition) then
    exit; //applies to token not yet created
//first description?
  p := item.RawDescriptionInfo;
  if p.Content = '' then begin
  //first description
    p.Content := T.CommentContent;
    p.StreamName := T.StreamName;
    p.BeginPosition := T.BeginPosition;
  end else begin
    p.Content := p.Content + LineEnding + t.CommentContent;
    if p.StreamName <> t.StreamName then
      p.StreamName := ' ';  //should never occur here!
  end;
  p.EndPosition := T.EndPosition;
  if fDestroy then
    FreeAndNil(t);
  Result := True;
end;

const
  SExpectedButFound = '%s expected but %s found';

procedure TParser.CheckToken(T: TToken; ATokenType: TTokenType);
begin
{$IFNDEF old}
//short version, error messages differ from old version! - really?
  if T.MyType <> ATokenType then
    DoError(SExpectedButFound, [TokenDefinition(ATokenType), T.Description]);
{$ELSE}
  if T.MyType <> ATokenType then begin
    if ATokenType >= KEY_AND then begin
    //key
      DoError(SExpectedButFound,
        [Format('reserved word "%s"', [LowerCase(TokenNames[ATokenType])]),
          T.Description]);
    end else if ATokenType >= SYM_PLUS then begin
    //symbol
      DoError(SExpectedButFound,
        [Format('symbol "%s"', [TokenNames[ATokenType]]),
          T.Description]);
    end else
      DoError(SExpectedButFound,
        [TokenNames[ATokenType],
          T.Description]);
  end;
{$ENDIF}
end;

{ ---------------------------------------------------------------------------- }

function TParser.Recorded(fStripLast: boolean): string;
begin
  Result := Recorder;
  if fStripLast then
    SetLength(Result, PrevRecordSize);
  Recorder := '';
end;

procedure TParser.ConsumeToken;
begin
//valid only after a PeekNextToken! (Peeked must not be Nil)
  assert(Peeked <> nil, 'illegal ConsumeToken');
  Token.Free;
  Token := Peeked;
  Peeked := nil;
  Recorder := Recorder + Token.Data;
end;

function TParser.GetNextToken: TTokenType;
begin
  Result := PeekNextToken;
  ConsumeToken;
end;

procedure TParser.Expect(tt: TTokenType);
begin
  if GetNextToken <> tt then
    CheckToken(Token, tt);
end;

function TParser.Skip(tt: TTokenType): boolean;
begin
  Result := PeekNextToken = tt;
  if Result then
    ConsumeToken;
end;

function TParser.Skip(dir: TStandardDirective): boolean;
begin
  Result := PeekNextToken = TOK_IDENTIFIER;
  if Result and (Peeked.Directive = dir) then
    ConsumeToken;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ApplyComments(item: TPasItem);
var
  t: TToken;

  procedure DiscardT;
  begin
    DoMessage(2, pmtWarning, 'Comment discarded: "%s"', [t.CommentContent]);
    FreeAndNil(t);
  end;

begin
(* After an item has been created, add all pending comments to it.
*)
  assert(item <> nil, 'cannot add comments to Nil');
  if assigned(BlockComment) and (BlockComment.BeginPosition < item.NamePosition) then
    AddDescription(BlockComment, item, False); //don't destroy!!!
  //else applies to following items only
//inspect all pending comments
  while Pending <> nil do begin
    t := Pending;
    Pending := t.Next;
    if t.StreamName <> item.NameStream then begin
      //DiscardT()
      DoMessage(1, pmtWarning,
        '%s: Different file: "%s"',
        [Scanner.GetStreamInfo, t.CommentContent]);
      FreeAndNil(t);
    end else if (t.Mark = cmFwd) then begin
      if t.EndPosition > item.NamePosition then
        break;  //applies to following item
      AddDescription(t, item);
    end else if t.BeginPosition < item.NamePosition then begin //back comment
      //DiscardT()
      DoMessage(1, pmtWarning,
        '%s: No target for back-comment: "%s"',
        [Scanner.GetStreamInfo, t.CommentContent]);
        FreeAndNil(t);
    end else
      AddDescription(t, item);
    assert(t=nil, 'comment not destroyed');
  end;
//all remaining comments apply to following items
end;

function TParser.CreateItem(AClass: TPasItemClass; tt: TTokenType;
  Ident: TToken): TPasItem;
begin
//get identifier
  if Ident = nil then
    Ident := QualID(True); //assume: must read the name
  Result := AClass.Create(CurScope, tt, Ident.Data);
  Result.NameStream := Ident.StreamName;
  Result.NamePosition := Ident.BeginPosition;
  ApplyComments(Result);
end;

function  TParser.QualID(fGet: boolean; fOperator: boolean): TToken;
//var lst: TNameParts; not stored, only by interpretation of given string!
begin
(* get an fully qualified name, remember first token.
*)
//assumed: <ident> { "." <ident> }
  if fGet then
    GetNextToken;
  if fOperator and (Token.MyType in
    [SYM_ASSIGN, SYM_PLUS, SYM_MINUS, SYM_ASTERISK, SYM_SLASH, SYM_POWER,
    SYM_EQUAL, SYM_LESS_THAN, SYM_LESS_THAN_EQUAL, SYM_GREATER_THAN, SYM_GREATER_THAN_EQUAL])
  then
    //okay
  else
    CheckToken(Token, TOK_IDENTIFIER);
//remember token
  Identifier := Token;
  Token := nil; //dangerous!!!
//collect qualifiers - the last token is the real identifier!
  while Skip(SYM_PERIOD) do begin
    Expect(TOK_IDENTIFIER);
    Identifier.Data := Identifier.Data + '.' + Token.Data;
  end;
//result, for convenience only
  Result := Identifier;
end;

{ ---------------------------------------------------------------------------- }

function  TParser.ParseCDFP(fClass: boolean;
  MethodType: TTokenType;
  Ident: TToken): TPasMethod;

  { Reads tokens (adding them to M.FullDeclaration) until a semicolon
    (on parenthesis level zero) is found (this final semicolon
    is also read and appended to M.FullDeclaration). }
  procedure ReadTokensUntilSemicolon;
  var
    level: integer;
  begin
    //Recorder := '';
    level := 0;
    repeat
      case GetNextToken of
      SYM_LEFT_PARENTHESIS: Inc(level);
      SYM_RIGHT_PARENTHESIS: dec(level);
      SYM_SEMICOLON: if level = 0 then break;
      end;
    until False;
    //M.FullDeclaration := M.FullDeclaration + Recorded;
  end;

  procedure PeekSemicolon;
  begin
    repeat
      GetNextToken; //record it!
    until PeekNextToken = SYM_SEMICOLON;
  end;

{ Apparently, the Delphi compiler does NOT enforce that
  directives must be separated and be terminated by a semicolon,
  even though Delphi help consistently uses them consistently.
  However, we take the compiler as a reference and try to mimic its behaviour.
}
  procedure InsertSemicolon;
  begin
    if Peeked.MyType = SYM_SEMICOLON then
      GetNextToken //consume and record
    else
      Recorder := Recorder + ';';
  end;

//var  InvalidType: boolean;
var
  M: TPasMethod absolute Result;
//const MClause: array[boolean] of TTokenType = (KEY_OBJECT, KEY_CLASS);
begin //ParseCDFP
{ Parses a constructor, a destructor, a function or a procedure
      or an operator (for FPC).

FPC grammar states that modifiers are separated by ";",
  but are not necessarily terminated by ";"
Delphi also doesn't require an ";" between modifiers!

Modifiers with arguments:
  ALIAS ":" string
  EXTERNAL [ string ]
  NAME string
  INDEX expr
The arguments can be identifiers, so that we should assume that
  modifiers with arguments are terminated by ";"
}
//parse method declaration
  if Ident = nil then
    Ident := QualID(True, True);  //allow for operator???
  M := CreateItem(TPasMethod, MethodType, Ident) as TPasMethod;

  DoMessage(5, pmtInformation, 'Parsing %s "%s"',
    //[MethodTypeToString(MethodType), M.Name]);
    [LowerCase(TokenNames[MethodType]), M.Name]);

  ReadTokensUntilSemicolon;

  { first get non-WC token - if it is not an identifier in SD_SET put it back
    into stream and leave; otherwise copy tokens until semicolon }
  repeat
    //case GetNextToken of
    case PeekNextToken of
    KEY_INLINE:   ;
    KEY_LIBRARY:  M.HasAttribute[SD_LIBRARY] := True; // .IsLibrarySpecific := True;
    TOK_IDENTIFIER:
      case Peeked.Directive of
      SD_ABSTRACT, SD_ASSEMBLER, SD_CDECL, SD_DYNAMIC, SD_EXPORT,
      SD_FAR, SD_FORWARD, SD_NEAR, SD_OVERLOAD, SD_OVERRIDE, SD_INLINE,
      SD_PASCAL, SD_REGISTER, SD_SAFECALL, SD_STATIC,
      SD_STDCALL, SD_REINTRODUCE, SD_VIRTUAL,
      SD_VARARGS,
      SD_DEPRECATED,  //M.IsDeprecated := True;
      SD_PLATFORM:    //M.IsPlatformSpecific := True;
        M.HasAttribute[Peeked.Directive] := True;
      { * External declarations might be followed by a string constant.
        * Messages are followed by an integer constant between 1 and 49151 which
          specifies the message ID. }
      SD_EXTERNAL, SD_MESSAGE, SD_NAME:
        begin
        // Keep on reading up to the next semicolon or declaration
          PeekSemicolon;
        end;
      SD_DISPID:  PeekSemicolon;
      else  //case directive
        //UnGetToken;
        Break;
      end;
    else //case type
      //UnGetToken;
      Break;
    end;
  (* We come here with either:
    PeekSemicolon: Peeked=";"
    or an valid unconsumed simple modifier
  *)
    if Peeked.MyType <> SYM_SEMICOLON then
      GetNextToken; //consume modifier
  //expect ";", but insert one if missing
    if not Skip(SYM_SEMICOLON) then
      Recorder := Recorder + ';';
  until False;

//we come here with an unrecognized peeked token
  //if not Skip(SYM_SEMICOLON) then Recorder := Recorder + ';';
  M.FullDeclaration := Recorded;
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseCIO(Ident: TToken;  //const CioName: string;
  CIOType: TTokenType;  const IsInRecordCase: boolean): TPasCio;

const
//recognized visibilities
  sVisibilities = [SD_PRIVATE, SD_PROTECTED, SD_PUBLIC, SD_PUBLISHED, SD_AUTOMATED];
  sAllVisibilities = sVisibilities + [SD_STRICT];
//recognized sections
  sSections = [KEY_VAR, KEY_CONST, KEY_TYPE]; { TODO : handle sections in class declarations }
var
  fClass: boolean;  //ClassKeyWordString: string;
  i: TPasCio absolute Result;

  procedure AddDefaultAncestor;

    procedure CheckFor(const s: string);
    begin
      if not SameText(i.Name, s) then
        i.Ancestors.Add(s);
    end;

  begin
  //add default ancestor, depending on CIO type
    case i.MyType of
      CIO_CLASS:  CheckFor('TObject');
      CIO_SPINTERFACE: CheckFor('IDispInterface');
      CIO_INTERFACE:  CheckFor('IInterface');
    end;
  end;

var
  //Finished: Boolean;
  //M: TPasMethod;
  //p: TPasProperty;
  Visibility: TVisibility;
  //s: string;
  //t: TToken;
  //StrictVisibility: boolean;
begin //ParseCIO
(* ident "=" ( class | interface | record | object ) <| body ";" |>
class = CLASS [ ABSTRACT | SEALED ] [ancestors] [guid]
or
  ident = CLASS <| ";" |>
*)
  //StrictVisibility := False;
  DoMessage(5, pmtInformation, 'Parsing class/interface/object "%s"',
    [Ident.Data]);  //[CioName]);
  //i := nil;
  { Test for forward class definition here:
      class MyClass = class;
    with no ancestor or class members listed after the word class. }
  if Skip(SYM_SEMICOLON) then
    Exit;  // No error, continue the parsing.

  i := CreateItem(TPasCio, CIOType, Ident) as TPasCio;

  if (Token.Directive in [SD_ABSTRACT, SD_SEALED]) then begin
    i.HasAttribute[Token.Directive] := True;
    GetNextToken;
  end;

  { get ancestor and all interfaces; remember, this could look like
    TNewClass = class ( Classes.TClass, MyClasses.TFunkyClass, MoreClasses.YAC) ... end;
    Every entry but the first must be an interface. }
  if Skip(SYM_LEFT_PARENTHESIS) and not Skip(SYM_RIGHT_PARENTHESIS) then begin
    repeat //parse ancestor (ident) list
    //start recording ancestor
      i.FullDeclaration := i.FullDeclaration + Recorded;
    {$IFDEF old}
      Expect(TOK_IDENTIFIER);
      while Skip(SYM_PERIOD) do
        Expect(TOK_IDENTIFIER);
    {$ELSE}
      QualId(True);
    {$ENDIF}
      i.Ancestors.Add(Recorder);
    until not Skip(SYM_COMMA);
    Expect(SYM_RIGHT_PARENTHESIS);
  end else
    AddDefaultAncestor;

//GUID?
  if Skip(SYM_LEFT_BRACKET) then begin
    GetNextToken;
    if not Skip(SYM_RIGHT_BRACKET) then
      DoError('Literal String or identifier as interface ID expected', []);
  end;
//finish declaration
  i.FullDeclaration := i.FullDeclaration + Recorded;

  if PeekNextToken <> SYM_SEMICOLON then begin
    { Else A declaration of type "name = class(ancestor);" }

  //default visibility
    if I.MyType = CIO_CLASS then begin
      { Visibility of members at the beginning of a class declaration
        that don't have a specified visibility is controlled
        by ImplicitVisibility value. }
      case ImplicitVisibility of
        ivPublic:
          if Scanner.SwitchOptions['M'] then
            Visibility := viPublished else
            Visibility := viPublic;
        ivPublished:
          Visibility := viPublished;
        ivImplicit:
          Visibility := viImplicit;
        else raise EInternalError.Create('ImplicitVisibility = ??');
      end;
    end else begin
      { Everything besides a class always starts with visibility "public". }
      Visibility := viPublic;
    end;
    i.CurVisibility := Visibility;

  { now collect methods, fields and properties }
    OpenScope(i);

    (* Sections are: visibility, newer OPL: local type, var... sections.
      END terminates the member list,
      everything else starts a member declaration.
    *)

    { This is needed to include ClassKeyWordString in
      class methods declarations. }
    fClass := False;  // ClassKeyWordString := '';

    //Finished := False;
    while GetNextToken <> KEY_END do begin  //repeat
      if Token.Directive in sAllVisibilities then begin
      //visibility
        case Token.Directive of
        SD_PRIVATE:   Visibility := viPrivate;
        SD_PROTECTED: Visibility := viProtected;
        SD_PUBLIC:    Visibility := viPublic;
        SD_PUBLISHED: Visibility := viPublished;
        SD_AUTOMATED: Visibility := viAutomated;
        SD_STRICT:
          if Skip(SD_PRIVATE) then
            Visibility := viStrictPrivate
          else if Skip(SD_PROTECTED) then
            Visibility := viStrictProtected
          else
            DoError('"strict" not applicable to ', [Peeked.Data]);
        end;
        Recorder := ''; //throw away recorded visibilites
        i.CurVisibility := Visibility;
        Continue;
      end;
    //peek sections
      if Token.MyType in sSections then begin
      //to be implemented
        DoError('unhandled section in CIO: %s', [Token.Description]);
      end;
    //everything else should be a member declaration
      case Token.MyType of
      //KEY_VAR:    ClassKeyWordString := Trim(ClassKeyWordString + ' ' + t.Data);
      KEY_CLASS:    fClass := True; // ClassKeyWordString := Token.Data;
      KEY_CONSTRUCTOR, KEY_DESTRUCTOR,
      KEY_FUNCTION, KEY_PROCEDURE:
        {M :=} ParseCDFP(fClass, Token.MyType, nil);
      //KEY_END: Finished := True;
      KEY_PROPERTY:
        {p :=} ParseProperty; //(i);  //, Visibility);
      KEY_CASE:
        ParseRecordCase(false);
      TOK_IDENTIFIER:
        ParseVariables(False);
      else  //case
        DoError('Unexpected %s', [Token.Description]);
      end;  //case
    end;  //member loop, skipped END
  //else peeked ";"
    CloseScope;
  end;  //parse item with members

  ParseHintDirectives(i);
//how can a record case occur just here???
  if GetNextToken <> SYM_SEMICOLON then begin
    if IsInRecordCase then begin
      if Token.MyType <> SYM_RIGHT_PARENTHESIS then begin
        DoError('Unexpected symbol at end of sub-record: %s', [Token.Description]);
      end;
    end else begin
      DoError('Semicolon at the end of Class / Object / Interface' +
        ' / Record expected', []);
    end;
  end;
//consumed either ")" or ";"
  //Recorder := ''; //drop eventual directives?
  i.FullDeclaration := i.FullDeclaration + Recorded;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseConstant;  //(const U: TPasUnit);
var
  i: TPasConstant;
begin
(* const ident <| [":" type] "=" value ";" |>
*)
  //Recorder := ''; - required?
  i := CreateItem(TPasConstant, KEY_CONST, QualId(False));
  DoMessage(5, pmtInformation, 'Parsing constant %s', [i.Name]);
  SkipDeclaration(True, i);
  i.FullDeclaration := Recorded;
  CheckToken(Token, SYM_SEMICOLON);
end;

{ ---------------------------------------------------------------------------- }

//function  TParser.ParseEnum(const Name: string): TPasEnum;
function  TParser.ParseEnum: TPasEnum;
var
  Item: TPasItem;
  ParenLevel: Integer;
  p: TPasEnum absolute Result;
begin
(* <| "(" ident ["=" value] { "," ident ["=" value] } ");"
*)
  TPasItem(p) := CreateItem(TPasEnum, KEY_TYPE, Identifier);
  p.FullDeclaration := Identifier.Data + ' = (...);';

  OpenScope(p);
  repeat  //while not Skip(SYM_RIGHT_PARENTHESIS) do begin
    Recorder := '';
    Item := CreateItem(TPasConstant, KEY_CONST, QualId(True));

    if Skip(SYM_EQUAL) then begin
    //value might be an expression?
      { Now read tokens until comma or right paren (but only on ParenLevel = 0). }
      ParenLevel := 0;
      repeat
        case GetNextToken of
        SYM_LEFT_PARENTHESIS, SYM_LEFT_BRACKET: Inc(ParenLevel);
        SYM_RIGHT_PARENTHESIS, SYM_RIGHT_BRACKET: Dec(ParenLevel);
        end;
      until (Token.MyType in [SYM_COMMA, SYM_RIGHT_PARENTHESIS])
        and (ParenLevel <= 0);
    //end with "," or ")"
    end else
      GetNextToken; //"," or ")"
  //eventually remove last token (delimiter) from Recorder
    Item.FullDeclaration := Recorded(True);
  until Token.MyType <> SYM_COMMA;

  Expect(SYM_SEMICOLON);
  //Recorder := '';
  CloseScope;
end;

procedure TParser.ParseInterfaceSection(const U: TPasUnit);
const
  MODE_UNDEFINED = 0;
  MODE_CONST = 1;
  MODE_TYPE = 2;
  MODE_VAR = 3;
var
  Finished: Boolean;
  Mode: Integer;
  //M: TPasMethod;
  //PropertyParsed: TPasProperty;
begin
(* INTERFACE |> { clauses } IMPLEMENTATION |>
clauses:
  USES <| id-list ";" |>
  (VAR | CONST ...) { ident <| vc-decl ";" } |>
  TYPE { ident <| type-decl ";" } |>
Procedures are special, due to possible modifiers?
All possible modifiers should be peeked!
*)
  DoMessage(4, pmtInformation, 'Entering interface section of unit %s',[U.Name]);
  Finished := False;
  Mode := MODE_UNDEFINED;

  repeat
    Recorder := '';
    case GetNextToken of
    KEY_USES: ParseUses(U);
    KEY_RESOURCESTRING, KEY_CONST:  Mode := MODE_CONST;
    KEY_TYPE:                       Mode := MODE_TYPE;
    KEY_THREADVAR, KEY_VAR:         Mode := MODE_VAR;
    TOK_IDENTIFIER: //or "operator"
      if Token.Directive = SD_OPERATOR then begin
        {M :=} ParseCDFP(false, Key_Operator, nil);
        Mode := MODE_UNDEFINED;
      end else begin
        case Mode of
        MODE_CONST: ParseConstant;  //(U);
        MODE_TYPE:  ParseType;  //(U);
        MODE_VAR:   ParseVariables(True); //(U);
        else //case
          DoError('Unexpected %s', [Token.Description]);
        end; //case
      end;
    KEY_FUNCTION, KEY_PROCEDURE:
      begin
        {M :=} ParseCDFP(False, Token.MyType, nil);
        Mode := MODE_UNDEFINED;
      end;
    KEY_PROPERTY:
      begin
        {PropertyParsed :=} ParseProperty;  //(U); //(PropertyParsed);
        Mode := MODE_UNDEFINED;
      end;
    KEY_IMPLEMENTATION:
      Finished := True;
    else //case
      DoError('Unexpected %s', [Token.Description]);
    end; //case
  until Finished;
end;

{ ---------------------------------------------------------------------------- }

//function  TParser.ParseProperty(U: TPasScope; Visibility: TVisibility): TPasProperty;
function  TParser.ParseProperty: TPasProperty;
//var  Finished: Boolean;
var
  p: TPasProperty absolute Result;
begin
(* "property" ident [ decl ] ";"
decl: [ params ] ":" type [index] [reader] [writer] [";"] [default *] [stored *]
  ";"
*)
  TPasItem(p) := CreateItem(TPasProperty, KEY_PROPERTY, nil);
  DoMessage(5, pmtInformation, 'Parsing property %s', [p.Name]);
  p.IndexDecl := '';
  p.Proptype := '';

{ Is this only a redeclaration of property from ancestor
    (to e.g. change it's visibility) }
  if Skip(SYM_SEMICOLON) then begin
    p.FullDeclaration := Recorded; //p.FullDeclaration + ';';
    Exit;
  end;

{ get index }
  p.FullDeclaration := Recorded; //separate optional parts
  if Skip(SYM_LEFT_BRACKET) then begin
    while GetNextToken <> SYM_RIGHT_BRACKET do
      ;
    p.IndexDecl := Recorder;
    p.FullDeclaration := p.FullDeclaration + Recorded;
  end;

{ now if there is a colon, it is followed by the type }
  if Skip(SYM_COLON) then begin
    { get property type }
    p.FullDeclaration := p.FullDeclaration + Recorded;  //add ":"
  //problem: separate type from possibly following directives
  //wait for ";" or directive
    while (PeekNextToken <> SYM_SEMICOLON)
    and (Peeked.Directive = SD_INVALIDSTANDARDDIRECTIVE) do
      GetNextToken;
    p.Proptype := Recorder; //keep, added to FullDeclaration
  end;

{ read the rest of declaration }
  SkipDeclaration(false, p); //doesn't read "default" etc., past first ";"
//skip further specifiers
  while (PeekNextToken = tok_identifier)
  and (Peeked.Directive in [sd_default, sd_nodefault, sd_stored]) do begin
    while GetNextToken <> sym_semicolon do
      ;
  end;
  p.FullDeclaration := p.FullDeclaration + Recorded;
//now past final ";"
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseRecordCase(const SubCase: boolean);
var
  P: TPasItem;
begin
(* CASE <| [ident ":"] type OF
  { ...":" "(" decl { ";" decl } ")" [";"] }
  |> END [ ";" ]

decl can be:
  CASE ... "(" ... ")"  [";"] ")" //<--- ")" instead of END!
*)
  Recorder := '';
  QualId(True); //name or type?
  if Skip(SYM_COLON) then begin
  { Then we have "case FieldName: FieldType of" }
    p := CreateItem(TPasItem, KEY_VAR, Identifier);
    while PeekNextToken <> Key_OF do
      GetNextToken;
    p.FullDeclaration := Recorded(True) + ';';
  end;

  Expect(KEY_OF);

  repeat  //sure that at least one case must exist?
  //why should we be stricter than the compiler???
    while GetNextToken <> SYM_COLON do
      ;
    Expect(SYM_LEFT_PARENTHESIS);

    //while not Skip(SYM_RIGHT_PARENTHESIS) do begin
    repeat
      if Skip(KEY_CASE) then
        ParseRecordCase(true)
      else begin
        Expect(TOK_IDENTIFIER);
        ParseVariables(False); //... ";" <| ")" <| ";"
        //CheckToken(Token, SYM_RIGHT_PARENTHESIS);
      end;
    until Token.MyType = SYM_RIGHT_PARENTHESIS; //else ";" before ")"
    Skip(SYM_SEMICOLON);
  //until Skip(KEY_END)or (SubCase and Skip(SYM_RIGHT_PARENTHESIS));
  until (PeekNextToken = KEY_END)
  or (SubCase and Skip(SYM_RIGHT_PARENTHESIS));
end;

procedure TParser.ParseType;  //(const U: TPasUnit);
var
  NormalType: TPasItem; //TPasType;
  TypeName: string;
begin
(* TYPE
  ident <| = [TYPE] decl ";" |>
decl can be
  CLASS OF ident
  CLASS [ancestors, guid] members... ";"
*)
  QualID(False);
  TypeName := Identifier.Data;
  DoMessage(5, pmtInformation, 'Parsing type "%s"', [TypeName]);

  if Skip(SYM_SEMICOLON) then
    Exit; //what's that???

  Expect(SYM_EQUAL);
  Skip(KEY_TYPE);
  {fPacked :=} Skip(KEY_PACKED);

  case GetNextToken of
  KEY_CLASS:
    if Skip(KEY_OF) then begin
      { include "identifier = class of something;" as standard type }
    end else begin
      ParseCIO(Identifier, Token.MyType, False);
      Exit;
    end;
  KEY_DISPINTERFACE,
  KEY_INTERFACE,
  KEY_OBJECT,
  KEY_RECORD: begin
      ParseCIO(Identifier, Token.MyType, False);
      Exit;
    end;
  end;

  if Token.MyType in [KEY_FUNCTION, KEY_PROCEDURE] then begin
    {MethodType :=} ParseCDFP(False, Token.MyType, Identifier);
  end else if Token.IsSymbol(SYM_LEFT_PARENTHESIS) then begin
    {EnumType :=} ParseEnum;  //(TypeName);
  end else begin
  { TODO : Treat <type>=<class> as class(<class>), for class tree construction
    and name search in ancestors. }
    NormalType := CreateItem(TPasType, KEY_TYPE, Identifier);
    SkipDeclaration(False, NormalType);
    NormalType.FullDeclaration := Recorded;
  end;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseUnit(U: TPasUnit);
begin
(* UNIT ident <| ";"
  INTERFACE ...
  IMPLEMENTATION |>
*)
  ParseHintDirectives(U);
  Expect(SYM_SEMICOLON);
  Expect(KEY_INTERFACE);

  { now parse the interface section of that unit }
  ParseInterfaceSection(U);
end;

{ ---------------------------------------------------------------------------- }
procedure TParser.ParseProgramOrLibraryUses(U: TPasUnit); //; fWithHeader: boolean);
begin
  ParseHintDirectives(U);
  Expect(SYM_SEMICOLON);

  if Skip(KEY_USES) then
    ParseUses(U);
end;

procedure TParser.ParseProgram(U: TPasUnit);
begin
//skip parameters
  if Skip(SYM_LEFT_PARENTHESIS) then begin
    while GetNextToken <> SYM_RIGHT_PARENTHESIS do
      ;
  end;
  ParseProgramOrLibraryUses(U);
end;

procedure TParser.ParseLibrary(U: TPasUnit);
begin
  ParseProgramOrLibraryUses(U);
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseUnitOrProgram(var U: TPasUnit);
//function  TParser.ParseUnitOrProgram: TPasUnit;
(* required by PasDoc_base!
*)
var
  tt: TTokenType;
begin
(* [ UNIT | LIBRARY | PROGRAM | PACKAGE ] ident ...
*)
  assert(CurScope = nil, 'old scope???');
  tt := GetNextToken;
  U := CreateItem(TPasUnit, tt, nil) as TPasUnit;
  U.CurVisibility := viPublic;
  OpenScope(U);
  case tt of
  KEY_UNIT:     ParseUnit(U);
  KEY_LIBRARY:  ParseLibrary(U);
  KEY_PROGRAM:  ParseProgram(U);
  else
    DoError('unrecognized file type: %s', [Token.Description]);
  end;
  CloseScope;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseUses(const U: TPasUnit);
begin
(* USES qualid { "," qualid } ";"
qualid (here)
  ident { "." ident } [ IN string ]
*)
  { Parsing uses clause clears the comment, otherwise
    - normal comments before "uses" clause would be assigned to normal unit
      items (like a procedure), which is quite unexpected
      (see ok_comment_over_uses_clause.pas testcase).
    - analogously, back comments after "uses" clause would be assigned to the unit
      description (see ok_comment_over_uses_clause_2.pas testcase).
  }
  CancelComments;
  //LastCommentMark := cmNoRem; //IsLastComment := false;
  //ItemsForNextBackComment.Clear;

  repeat
    //U.UsesUnits.Append(GetAndCheckNextToken(TOK_IDENTIFIER, true));
    U.UsesUnits.Append(QualId(True).Data);

    if Skip(KEY_IN) then begin
    { Below we just ignore the value of next string token.

      We can do this -- because PasDoc (at least for now)
      does not recursively parse units on "uses" clause.
      So we are not interested in the value of
      given string (which should be a file-name (usually relative,
      but absolute is also allowed AFAIK) with given unit.)

      If we will ever want to implement such "recursive parsing
      of units" in PasDoc, we will have to fix this to
      *not* ignore value of token below.
    }
      Expect(TOK_STRING);
    end;
  until not Skip(SYM_COMMA);
  Expect(SYM_SEMICOLON);
end;

//function TParser.ParseIdentList(AClass: TPasItemClass; tt: TTokenType): TPasItem;
function TParser.ParseVarList(): TPasItem;
const
  AClass: TPasItemClass = TPasFieldVariable;
  tt = KEY_VAR;
begin
(* ident <| { "," ident } |>
*)
  Result := CreateItem(AClass, tt, QualID(False));
  while Skip(SYM_COMMA) do begin
    //Expect(TOK_IDENTIFIER);
    CreateItem(AClass, tt, nil);
  end;
//next token peeked, but not consumed (typically: ":")
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseVariables(inUnit: boolean);

  // The section allows PasDoc to parse variable modifiers in FPC.
  // See: http://www.freepascal.org/docs-html/ref/refse19.html
  // This consumes some tokens and appends to ItemCollector.FullDeclaration.
  procedure ParseVariableModifiers(ItemCollector: TPasItem);
  begin
  (* <| { CVAR | EXPORT | PUBLIC | EXTERNAL ... ";" } |>
  *)
    while True do begin
      PeekNextToken;
      if not (Peeked.Directive in [SD_CVAR, SD_EXPORT, SD_EXTERNAL, SD_PUBLIC]) then
        break;  //not an expected directive
    //skip including ";"
      while GetNextToken <> SYM_SEMICOLON do
        ;
    end;
  end;

var
  FirstItem, NewItem: TPasItem;
  I: Integer;
{
  NewItem: TPasFieldVariable;
  ItemCollector: TPasFieldVariable;
  m: TPasMethod;
  NewItemNames: TStringList;
  RawDescriptions: TRawDescriptionInfoList;
  NewItems: TPasItems;
}
begin //ParseFieldsVariables
(* ident <| { "," ident } ":" type [absolute] ";" modifiers |>
*)
//parse ident list
  //QualID(False);
  FirstItem := ParseVarList;
//record type
  Recorder := '';
  Expect(SYM_COLON);
  SkipDeclaration(False, FirstItem);
//past ";" or ")" or END
  if inUnit then  //modifiers apply only to unit variables
    ParseVariableModifiers(FirstItem);

(* Propagate into all new items:
  - recorded declaration
  - recorded attributes
*)
  for I := CurScope.Members.Count - 1 downto 0 do begin
    NewItem := CurScope.Members.PasItemAt[i];
    NewItem.FullDeclaration := NewItem.Name + Recorder;
    if NewItem = FirstItem then
      break;  //this one already finished
    NewItem.Attributes := FirstItem.Attributes;
  end;
  Recorder := '';
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.SetCommentMarkers(const Value: TStringList);
begin
  FCommentMarkers.Assign(Value);
end;

{$IFDEF old}
procedure TParser.SkipDeclaration(const Item: TPasItem; IsInRecordCase: boolean);
var
  EndLevel: Integer;
  IsSemicolon: Boolean;
  PLevel: Integer;
  //WhitespaceCollector: string;
begin
(* intended use: skip all type specifiers after ":" (ref) or "=" (decl).
Take into account (nesting level) embedded:
  pairs of "()"
  structured type definitions (RECORD, CLASS? ..END)
    (best all CIO types)
  pairs of "[]" (property index specifier

  Terminate on nesting level 0, when either token is found:
  ";" ordinary declaration --> include following modifiers!?
  ")" end of argument or record case list
  "]" end of property index specifier
  END of record (case)
*)
{ Read all tokens until you find a semicolon at brace-level 0 and
  end-level (between "record" and "end" keywords) also 0.

  Alternatively, also stops before reading "end" without beginning
  "record" (so it can handle some cases where declaration doesn't end
  with semicolon).

  Alternatively, only if IsInRecordCase, also stops before reading
  ')' without matching '('. That's because fields' declarations
  inside record case may be terminated by just ')' indicating
  that this case clause terminates, without a semicolon.

  If you pass Item <> nil then all read data will be
  appended to Item.FullDeclaration. Also Item.IsLibrarySpecific,
  Item.IsPlatformSpecific and Item.IsDeprecated will be set to true
  if appropriate hint directive will occur in source file.
}
  EndLevel := 0;
  PLevel := 0;
  repeat
    case GetNextToken of
    SYM_LEFT_PARENTHESIS: Inc(PLevel);
    SYM_RIGHT_PARENTHESIS: Dec(PLevel);
    KEY_END: Dec(EndLevel);
    KEY_RECORD: Inc(EndLevel);
    KEY_LIBRARY: if Assigned(Item) then Item.IsLibrarySpecific := true;
    TOK_IDENTIFIER:
      case Token.Directive of
      SD_PLATFORM:    if Assigned(Item) then Item.IsPlatformSpecific := true;
      SD_DEPRECATED:  if Assigned(Item) then Item.IsDeprecated := true;
      end;
    end; //case
    IsSemicolon := Token.IsSymbol(SYM_SEMICOLON);

    { Reason for "EndLevel < 0" condition:
        Within records et al. the last declaration need not be terminated by ;
      Reason for "(PLevel < 0) and IsInRecordCase" condition:
        See autodoc of SkipDeclaration in TParser interface. }
    if (EndLevel < 0) or
       ( (PLevel < 0) and IsInRecordCase ) then
    begin
      //Scanner.UnGetToken(t);
      Exit;
    end;
    //if Assigned(Item) then Item.FullDeclaration := Item.FullDeclaration + t.Data;
  until IsSemicolon and (EndLevel = 0) and (PLevel = 0);
end;
{$ELSE}
procedure TParser.SkipDeclaration(fSkipNext: boolean; CurItem: TPasItem);
var
  Level: Integer;
begin
(* intended use: skip all type specifiers after ":" (ref) or "=" (decl).
Take into account (nesting level) embedded:
  pairs of "()"
  structured type definitions (RECORD, CLASS? ..END)
    (best all CIO types)
  pairs of "[]" (property index specifier

  Terminate on nesting level 0, when either token is found:
  ";" ordinary declaration --> include following modifiers!?
  ")" end of argument or record case list
  "]" end of property index specifier
  END of record (case)
*)
  if fSkipNext and not (GetNextToken in [SYM_EQUAL, SYM_COLON]) then
    DoError('expected "=" or ":", got: %s', [Token.Description]);

  Level := 0;
  repeat
    case GetNextToken of
    SYM_LEFT_BRACKET,
    SYM_LEFT_PARENTHESIS: Inc(Level);
    SYM_RIGHT_BRACKET,
    SYM_RIGHT_PARENTHESIS: Dec(Level);
    SYM_SEMICOLON: if level = 0 then break; // Dec(Level);
    KEY_END: Dec(Level);
    KEY_CLASS, KEY_INTERFACE, KEY_DISPINTERFACE, KEY_OBJECT,
    KEY_RECORD: Inc(Level);
    KEY_LIBRARY: if Assigned(CurItem) then //CurItem.IsLibrarySpecific := true;
      CurItem.HasAttribute[SD_LIBRARY] := True;
    TOK_IDENTIFIER:
      case Token.Directive of
      SD_PLATFORM,
      SD_DEPRECATED:  if Assigned(CurItem) then CurItem.HasAttribute[Token.Directive] := true;
      end;
    end; //case
  until Level < 0;
(* /regular description should always end with a ";",
  even if a ")" or "END" was reached
*)
  Recorder := Recorded(True) + ';';
end;
{$ENDIF}

{ ------------------------------------------------------------ }

procedure TParser.ParseHintDirectives(Item: TPasItem);
begin
(* <| { LIBRARY | PLATFORM | DEPRECATED } |>
*)
  while True do begin
    if Skip(KEY_LIBRARY)        then //Item.IsLibrarySpecific := true
      Item.HasAttribute[SD_LIBRARY] := True
    else if Skip(SD_PLATFORM)   //then Item.IsPlatformSpecific := true
          or Skip(SD_DEPRECATED) then //Item.IsDeprecated := true
            item.HasAttribute[Token.Directive] := True
    else
      break;
  end;  //until false;
end;

function TParser.CloseScope: TPasScope;
begin
  Result := CurScope; //old scope, to be closed
  pointer(CurScope) := ScopeStack.Last;
  ScopeStack.Delete(ScopeStack.Count - 1);
end;

procedure TParser.OpenScope(AScope: TPasScope);
begin
  ScopeStack.Add(CurScope);
  CurScope := AScope;
end;

class function TParser.ShowVisibilities: TVisibilities;
begin
  Result := PasDoc_items.ShowVisibilities;
end;

end.
