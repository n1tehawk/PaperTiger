unit HttpClient;

{$mode objfpc}{$H+}
{ Adapted from original httpclient}

interface

uses
  FPHTTPClient, FPJSON, JSONParser, SysUtils, Classes;

type
  THttpResult = record
    Code: Integer;
    Text: string;
  end;

  TRequestMethod = (rmGet, rmHead, rmOptions, rmPost, rmPut, rmDelete);

  //todo: add timeout support
  // Perform a POST with JSON data and a file in multipart/form data. Return response in Response
function FileFormPostWithDataStream(const AData: TJSONData; const AURL, AFieldName: String;
  AFile: TStream; const AFileName: string): THttpResult;
// Perform a get etc and return JSON result data in AResponse
function HttpRequest(const AUrl: string; out AResponse: TJSONData;
  const AMethod: TRequestMethod = rmGet): THttpResult;
// Perform a post etc with JSON data in the request body and return JSON result data in AData
function HttpRequestWithData(var AData: TJSONData; const AUrl: string;
  const AMethod: TRequestMethod = rmPost;
  const AContentType: string = 'application/json'): THttpResult;
// Perform a post etc with JSON data in the request body and return the result body as a memory stream
// AContentType is filled with return data content type
function HttpRequestWithDataStream(var AData: TJSONData; const AUrl: string;
  const ReturnStream: TMemoryStream;
  const AMethod: TRequestMethod = rmPost;
  var AContentType: string = 'application/json'
  ): THttpResult;


implementation

// adapted from TFPCustomHTTPClient
function FileFormPostWithDataStream(const AData: TJSONData; const AURL, AFieldName: String;
  AFile: TStream; const AFileName: string):THttpResult;
const
  CRLF=#13+#10;
  VMethod='POST';
var
  BoundaryMarker: string;
  VHttp: TFPHTTPClient;
  VJSON: TJSONStringType;
  S : string;
  SS : TStringStream;
  F : TFileStream;
  VData: TMemoryStream; //result
begin
  BoundaryMarker:=Format('%.8x_multipart_boundary',[Random($ffffff)]);
  VHttp := TFPHTTPClient.Create(nil);
  VData := TMemoryStream.Create;
  try
    VHttp.RequestHeaders.Add('Connection: Close');
    // File part
    VHTTP.AddHeader('Content-Type','multipart/form-data; boundary='+BoundaryMarker);
    S:='--'+BoundaryMarker+CRLF; //only last one has trailing --
    s:=s+Format('Content-Disposition: form-data; name="%s"; filename="%s"'+CRLF,
      [AFieldName,ExtractFileName(AFileName)]);
    s:=s+'Content-Type: application/octet-string'+CRLF+CRLF;
    // Start with form-data filename
    SS:=TStringStream.Create(s);
    try
      // then add file part...
      SS.Seek(0,soFromEnd);
      SS.CopyFrom(AFile,AFile.Size);
      // ... then separator
      if Assigned(AData) then
      begin
        S:=CRLF+'--'+BoundaryMarker+CRLF; //only last one has trailing --
        SS.WriteBuffer(S[1],Length(S));
        // Add JSON part
        //todo move json part up front before file?
        S:='--'+BoundaryMarker+CRLF;
        s:=s+'Content-Disposition: form-data; name="JSON"'+CRLF;
        s:=s+'Content-Type: application/json'+CRLF+CRLF;
        SS.Seek(0,soFromEnd);
        SS.WriteBuffer(s[1],Length(S));
        SS.WriteBuffer(AData.AsJSON,Length(AData.AsJSON));
      end;
      S:=CRLF+'--'+BoundaryMarker+'--'+CRLF; //final separator has trailing --
      SS.WriteBuffer(S[1],Length(S));
      SS.Position:=0;
      VHttp.RequestBody:=SS;
      VHttp.HTTPMethod(VMethod, AUrl, VData, []);
      //todo: possibly parse json response
      Result.Code := VHttp.ResponseStatusCode;
      Result.Text := VHttp.ResponseStatusText;
    finally
      SS.Free;
      VData.Free;
    end;
  finally
    VHttp.Free;
  end;
end;


function HttpRequest(const AUrl: string; out AResponse: TJSONData;
  const AMethod: TRequestMethod): THttpResult;
var
  VMethod: string;
  VParser: TJSONParser;
  VHttp: TFPHTTPClient;
  VData: TMemoryStream;
begin
  VHttp := TFPHTTPClient.Create(nil);
  VData := TMemoryStream.Create;
  try
    case AMethod of
      rmDelete: VMethod := 'DELETE';
      rmGet: VMethod := 'GET';
      rmHead: VMethod := 'HEAD';
      rmOptions: VMethod := 'OPTIONS';
      rmPost: VMethod := 'POST';
    else
      raise Exception.Create('HttpRequest: Invalid request method.');
    end;
    VHttp.HTTPMethod(VMethod, AUrl, VData, []);
    Result.Code := VHttp.ResponseStatusCode;
    Result.Text := VHttp.ResponseStatusText;
    if VData.Size > 0 then
    begin
       if Assigned(AResponse) then
       begin
         VData.Position := 0;
         VParser := TJSONParser.Create(VData);
         try
           try
             AResponse := VParser.Parse;
           except
             //error occurred, e.g. we have regular HTML instead of JSON
             AResponse := nil; //caller has to check for nil
           end;
         finally
           VParser.Free;
         end;
       end
       else
       begin
         // We need an assigned Aresponse...
         AResponse := nil;
       end;
    end;
  finally
    VData.Free;
    VHttp.Free;
  end;
end;

function HttpRequestWithData(var AData: TJSONData; const AUrl: string;
  const AMethod: TRequestMethod; const AContentType: string): THttpResult;
var
  VMethod: string;
  VHttp: TFPHTTPClient;
  VParser: TJSONParser;
  VData: TMemoryStream;
  VJSON: TJSONStringType;
begin
  VHttp := TFPHTTPClient.Create(nil);
  VData := TMemoryStream.Create;
  try
    case AMethod of
      rmDelete: VMethod := 'DELETE';
      rmGet: VMethod := 'GET';
      rmPost: VMethod := 'POST';
      rmPut: VMethod := 'PUT';
    else
      raise Exception.Create('HttpRequest: Invalid request method.');
    end;
    if Assigned(AData) then
    begin
      VHttp.RequestBody := TMemoryStream.Create;
      VJSON := AData.AsJSON;
      VHttp.RequestBody.Write(Pointer(VJSON)^, Length(VJSON));
      VHttp.RequestBody.Position := 0;
    end;
    VHttp.AddHeader('Content-Type', AContentType);
    VHttp.HTTPMethod(VMethod, AUrl, VData, []);
    Result.Code := VHttp.ResponseStatusCode;
    Result.Text := VHttp.ResponseStatusText;
    if VData.Size > 0 then
    begin
      FreeAndNil(AData);
      VData.Position := 0;
      VParser := TJSONParser.Create(VData);
      try
        try
          AData := VParser.Parse;
        except
          //error occurred, e.g. we have regular HTML instead of JSON
          on E: Exception do
          begin
            FreeAndNil(AData); //caller has to check for Assigned(AData)
          end;
        end;
      finally
        VParser.Free;
      end;
    end
    else
    begin
      // No valid JSON data
      FreeAndNil(AData); //caller has to check for Assigned(AData)
    end;
  finally
    VHttp.RequestBody.Free;
    VHttp.RequestBody := nil;
    VData.Free;
    VHttp.Free;
  end;
end;

function HttpRequestWithDataStream(var AData: TJSONData; const AUrl: string;
  const ReturnStream: TMemoryStream;
  const AMethod: TRequestMethod;
  var AContentType: string): THttpResult;
var
  VMethod: string;
  VHttp: TFPHTTPClient;
  VJSON: TJSONStringType;
begin
  VHttp := TFPHTTPClient.Create(nil);
  try
    case AMethod of
      rmDelete: VMethod := 'DELETE';
      rmGet: VMethod := 'GET';
      rmPost: VMethod := 'POST';
      rmPut: VMethod := 'PUT';
    else
      raise Exception.Create('HttpRequest: Invalid request method.');
    end;
    if Assigned(AData) then
    begin
       if AContentType='' then
         AContentType:='application/json';
      VHttp.RequestBody := TMemoryStream.Create;
      VJSON := AData.AsJSON;
      VHttp.RequestBody.Write(Pointer(VJSON)^, Length(VJSON));
      VHttp.RequestBody.Position := 0;
    end
    else
    begin
      if AContentType='' then
        AContentType:='text/plain';
    end;
    VHttp.AddHeader('Content-Type', AContentType);
    VHttp.HTTPMethod(VMethod, AUrl, ReturnStream, []);
    Result.Code := VHttp.ResponseStatusCode;
    Result.Text := VHttp.ResponseStatusText;
    VHTTP.ResponseHeaders.NameValueSeparator := ':'; //needt to catch e.g. Content-Type: application/json
    AContentType := VHttp.ResponseHeaders[VHttp.ResponseHeaders.IndexOfName('Content-Type')];
  finally
    VHttp.RequestBody.Free;
    VHttp.RequestBody := nil;
    VHttp.Free;
  end;
end;

end.
