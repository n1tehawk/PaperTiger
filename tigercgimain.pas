unit tigercgimain;
{ CGI server part of papertiger.

  Copyright (c) 2013 Reinier Olislagers

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
}

{$i tigerserver.inc}

interface

uses
  SysUtils, Classes, httpdefs, fpHTTP, fpWeb,
  tigerservercore;

type

  { TFPWebModule1 }

  TFPWebModule1 = class(TFPWebModule)
    procedure deletedocumentRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
    procedure listRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
    procedure scanRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
    procedure serverinfoRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
    procedure showdocumentRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
    procedure unsupportedRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
    procedure uploadimageRequest(Sender: TObject; ARequest: TRequest;
      AResponse: TResponse; var Handled: Boolean);
  private
    { private declarations }
    FTigerCore: TTigerServerCore;
  public
    { public declarations }
    constructor Create;
    destructor Destroy; override;
  end;

var
  FPWebModule1: TFPWebModule1;

implementation

{$R *.lfm}

{ TFPWebModule1 }

procedure TFPWebModule1.deletedocumentRequest(Sender: TObject;
  ARequest: TRequest; AResponse: TResponse; var Handled: Boolean);
begin
  AResponse.Contents.Add('<p>todo: support method '+ARequest.QueryString+'.</p>' );
  Handled := true;
end;

procedure TFPWebModule1.listRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: Boolean);
begin
  {$IFDEF DEBUG}
  AResponse.Contents.Add('<p>papertiger build date: '+{$INCLUDE %DATE%}+' '+{$INCLUDE %TIME%}+'</p>');
  {$ENDIF}
  AResponse.Contents.Add('<p>List of documents:</p>');
  try
    AResponse.Contents.Add(FTigerCore.ListDocuments(''));
  except
    on E: Exception do
    begin
      AResponse.Contents.Add('todo: debug: exception '+E.Message);
    end;
  end;
  Handled:=true;
end;

procedure TFPWebModule1.scanRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: Boolean);
begin
  AResponse.Contents.Add('<p>todo: support method '+ARequest.QueryString+'.</p>' );
  Handled := true;
end;

procedure TFPWebModule1.serverinfoRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: Boolean);
begin
  AResponse.Contents.Add('<p>'+StringReplace(FTigerCore.ServerInfo,LineEnding,#13+#10,[rfReplaceAll])+'</p>');
  Handled := true;
end;

procedure TFPWebModule1.showdocumentRequest(Sender: TObject;
  ARequest: TRequest; AResponse: TResponse; var Handled: Boolean);
begin
  AResponse.Contents.Add('<p>todo: support method '+ARequest.QueryString+'.</p>' );
  Handled := true;
end;

procedure TFPWebModule1.unsupportedRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: Boolean);
begin
  AResponse.Contents.Add('<p>Unsupported method.</p>' );
  Handled := true;
end;

procedure TFPWebModule1.uploadimageRequest(Sender: TObject; ARequest: TRequest;
  AResponse: TResponse; var Handled: Boolean);
begin
  AResponse.Contents.Add('<p>todo: support method '+ARequest.QueryString+'.</p>' );
  Handled := true;
end;

constructor TFPWebModule1.Create;
begin
  FTigerCore:=TTigerServerCore.Create;
end;

destructor TFPWebModule1.Destroy;
begin
  FTigerCore.Free;
  inherited Destroy;
end;

initialization
  RegisterHTTPModule('TFPWebModule1', TFPWebModule1);
end.

