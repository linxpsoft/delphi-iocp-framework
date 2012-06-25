unit IocpServerMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, IocpTcpSocket, StdCtrls, ExtCtrls, SyncObjs, VaniFunc, IocpLogger;

{$define __SND_FIXED_SIZE__}

const
  TEST_PACK_SIZE = 256;
  
type
  TTestIocpServer = class(TSimpleIocpTcpServer)
  protected
    function TriggerClientRecvData(Client: TIocpSocketConnection; buf: Pointer; len: Integer): Boolean; override;
  end;

  TfmIocpServer = class(TForm)
    Timer1: TTimer;
    Panel1: TPanel;
    Panel2: TPanel;
    btnStart: TButton;
    btnStop: TButton;
    edtPort: TLabeledEdit;
    lbConnections: TLabel;
    lbSentBytes: TLabel;
    lbRecvBytes: TLabel;
    lbHandleUsedMemory: TLabel;
    lbHandleFreeMemory: TLabel;
    lbIoUsedMemory: TLabel;
    lbIoFreeMemory: TLabel;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    lbRunTime: TLabel;
    Label13: TLabel;
    lbSndQueueUsedMemory: TLabel;
    lbSndQueueFreeMemory: TLabel;
    Label15: TLabel;
    Label16: TLabel;
    cbConsole: TCheckBox;
    lbPendingRequest: TLabel;
    Label7: TLabel;
    edtTimeout: TLabeledEdit;
    edtLife: TLabeledEdit;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure cbConsoleClick(Sender: TObject);
  private
    FServer: TTestIocpServer;
    FStartTick: DWORD;
    FLastTick: DWORD;
    FLastSentBytes, FLastRecvBytes: Int64;

    procedure UpdateInfo;
  public
    { Public declarations }
  end;

var
  fmIocpServer: TfmIocpServer;

implementation

{$R *.dfm}

const
  KBYTES = Int64(1024);
  MBYTES = KBYTES * 1024;
  GBYTES = MBYTES * 1024;
  TBYTES = GBYTES * 1024;

function BytesToStr(Bytes: Int64): string;
begin
  if (Bytes = 0) then
    Result := ''
  else if (Bytes < KBYTES) then
    Result := Format('%dB', [Bytes])
  else if (Bytes < MBYTES) then
    Result := Format('%dK ', [Bytes div KBYTES]) + BytesToStr(Bytes mod KBYTES)
  else if (Bytes < GBYTES) then
    Result := Format('%dM ', [Bytes div MBYTES]) + BytesToStr(Bytes mod MBYTES)
  else if (Bytes < TBYTES) then
    Result := Format('%dG ', [Bytes div GBYTES]) + BytesToStr(Bytes mod GBYTES)
  else
    Result := Format('%dT ', [Bytes div TBYTES]) + BytesToStr(Bytes mod TBYTES);
end;

procedure TfmIocpServer.btnStartClick(Sender: TObject);
begin
  if (edtPort.Text = '') then
  begin
    zMsgWarning(Handle, '���ò�����');
    Exit;
  end;

  FServer.Timeout := StrToIntDef(edtTimeout.Text, 0) * 1000;
  FServer.ClientLife := StrToIntDef(edtLife.Text, 0) * 1000;
  FServer.Port := StrToInt(edtPort.Text);
  btnStart.Enabled := not FServer.Start;
  btnStop.Enabled := not btnStart.Enabled;
end;

procedure TfmIocpServer.btnStopClick(Sender: TObject);
begin
  btnStart.Enabled := FServer.Stop;
  btnStop.Enabled := not btnStart.Enabled;
end;

procedure TfmIocpServer.cbConsoleClick(Sender: TObject);
begin
  ShowConsoleLog(cbConsole.Checked);
end;

procedure TfmIocpServer.FormCreate(Sender: TObject);
begin
  {$ifdef WIN64}
  Caption := Caption + '(x64)';
  {$else}
  Caption := Caption + '(x86)';
  {$endif}
  FStartTick := GetTickCount;
  FServer := TTestIocpServer.Create(nil);
end;

procedure TfmIocpServer.FormDestroy(Sender: TObject);
begin
  FServer.Free;
end;

procedure TfmIocpServer.Timer1Timer(Sender: TObject);
begin
  UpdateInfo;
end;

procedure TfmIocpServer.UpdateInfo;
  function SpeedInfo(NowBytes, LastBytes: Int64; LastTick: DWORD): string;
  var
    t: DWORD;
  begin
    Result := BytesToStr(NowBytes);

    if (NowBytes > LastBytes) then
    begin
      t := CalcTickDiff(LastTick, GetTickCount);
      if (t > 0) then
        Result := Result + ', ' + BytesToStr(Round((NowBytes-LastBytes)/t)*1000) + '/��';
    end;
  end;
begin
  lbRunTime.Caption := TickToTimeStr(CalcTickDiff(FStartTick, GetTickCount));
  lbConnections.Caption := IntToStr(FServer.ConnectionList.Count);
  lbSentBytes.Caption := SpeedInfo(FServer.SentBytes, FLastSentBytes, FLastTick);
  lbRecvBytes.Caption := SpeedInfo(FServer.RecvBytes, FLastRecvBytes, FLastTick);
  lbHandleUsedMemory.Caption := BytesToStr(FServer.ConnectionUsedMemory);
  lbHandleFreeMemory.Caption := BytesToStr(FServer.ConnectionFreeMemory);
  lbIoUsedMemory.Caption := BytesToStr(FServer.PerIoUsedMemory);
  lbIoFreeMemory.Caption := BytesToStr(FServer.PerIoFreeMemory);
  lbSndQueueUsedMemory.Caption := BytesToStr(FServer.IoCacheUsedMemory);
  lbSndQueueFreeMemory.Caption := BytesToStr(FServer.IoCacheFreeMemory);
  lbPendingRequest.Caption := IntToStr(FServer.PendingRequest);

  FLastSentBytes := FServer.SentBytes;
  FLastRecvBytes := FServer.RecvBytes;
  FLastTick := GetTickCount;
end;

{ TTestIocpServer }

function TTestIocpServer.TriggerClientRecvData(Client: TIocpSocketConnection;
  buf: Pointer; len: Integer): Boolean;
var
{$ifdef __SND_FIXED_SIZE__}
  NewBuf: array [0..TEST_PACK_SIZE - 1] of Byte;
{$else}
  NewBuf: PByteArray;
{$endif}
  i: Integer;
begin
  Result := inherited TriggerClientRecvData(Client, buf, len);
  if not Result then Exit;

{$ifdef __SND_FIXED_SIZE__}
  for i := 0 to TEST_PACK_SIZE - 1 do
  begin
    NewBuf[i] := i mod 256;
  end;
  Result := (Client.Send(@NewBuf[0], TEST_PACK_SIZE) > 0);
{$else}
  GetMem(NewBuf, len);
  for i := 0 to len - 1 do
  begin
    NewBuf[i] := i mod 256;
  end;
  Result := (Client.Send(NewBuf, len) > 0);
  FreeMem(NewBuf);
{$endif}
end;

end.
