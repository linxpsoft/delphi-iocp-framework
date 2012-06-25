unit IocpMemoryPool;

//{$define __ZERO_MEMORY__}
{$DEFINE __HEAP_ALLOC__}

interface

uses
  Windows, Classes, SysUtils, SyncObjs, IocpLogger;

type
  TIocpMemoryPool = class
  private
    FRefCount: Integer;
    {$IFDEF __HEAP_ALLOC__}
    FHeapHandle: THandle;
    {$ENDIF}
    FBlockSize, FMaxFreeBlocks: Integer;
    FFreeMemoryBlockList: TList; // 经过实际测试，使用Classes.TList比Collections.TList<>效率更高
    FUsedMemoryBlockList: TList;
    FLocker: TCriticalSection;

    function GetFreeBlocks: Integer;
    function GetFreeBlocksSize: Integer;
    function GetUsedBlocks: Integer;
    function GetUsedBlocksSize: Integer;
    procedure SetMaxFreeBlocks(MaxFreeBlocks: Integer);
  public
    constructor Create(BlockSize, MaxFreeBlocks: Integer); virtual;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;
    function AddRef: Integer;
    function Release: Boolean;
    function GetMemory: Pointer;
    procedure FreeMemory(var P: Pointer);
    procedure Clear;

    property FreeMemoryBlockList: TList read FFreeMemoryBlockList;
    property UsedMemoryBlockList: TList read FUsedMemoryBlockList;
    property BlockSize: Integer read FBlockSize;
    property FreeBlocks: Integer read GetFreeBlocks;
    property FreeBlocksSize: Integer read GetFreeBlocksSize;
    property UsedBlocks: Integer read GetUsedBlocks;
    property UsedBlocksSize: Integer read GetUsedBlocksSize;
    property MaxFreeBlocks: Integer read FMaxFreeBlocks write SetMaxFreeBlocks;
  end;

implementation

{ TIocpMemoryPool }

constructor TIocpMemoryPool.Create(BlockSize, MaxFreeBlocks: Integer);
begin
  // 块大小以64字节对齐，这样的执行效率最高
  if (BlockSize mod 64 = 0) then
    FBlockSize := BlockSize
  else
    FBlockSize := (BlockSize div 64) * 64 + 64;
    
  FMaxFreeBlocks := MaxFreeBlocks;
  FFreeMemoryBlockList := TList.Create;
  FUsedMemoryBlockList := TList.Create;
  FLocker := TCriticalSection.Create;
  {$IFDEF __HEAP_ALLOC__}
  FHeapHandle := GetProcessHeap;
  {$ENDIF}
  FRefCount := 1;
end;

destructor TIocpMemoryPool.Destroy;
begin
  Clear;

  FFreeMemoryBlockList.Free;
  FUsedMemoryBlockList.Free;
  FLocker.Free;
  
  inherited Destroy;
end;

procedure TIocpMemoryPool.Lock;
begin
  FLocker.Enter;
end;

procedure TIocpMemoryPool.Unlock;
begin
  FLocker.Leave;
end;

function TIocpMemoryPool.AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TIocpMemoryPool.Release: Boolean;
begin
  Result := (InterlockedDecrement(FRefCount) = 0);
  if Result then Free;
end;

function TIocpMemoryPool.GetMemory: Pointer;
begin
  Lock;
  try
    Result := nil;

    // 从空闲内存块列表中取一块
    if (FFreeMemoryBlockList.Count > 0) then
    begin
      Result := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
    end;

    // 如果没有空闲内存块，分配新的内存块
    if (Result = nil) then
    begin
      {$IFDEF __HEAP_ALLOC__}
      Result := HeapAlloc(FHeapHandle, 0, FBlockSize);
      {$ELSE}
      Result := Pointer(GlobalAlloc(GPTR, FBlockSize));
      {$ENDIF}
      AddRef;
    end;

    if (Result <> nil) then
    begin
      {$ifdef __ZERO_MEMORY__}
      // 清零内存块
      ZeroMemory(Result, FBlockSize);
      {$endif}
      // 将取得的内存块放入已使用内存块列表
      FUsedMemoryBlockList.Add(Result);
    end else
      raise Exception.CreateFmt('分配内存块失败，块大小: %d', [FBlockSize]);
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.FreeMemory(var P: Pointer);
begin
  if (P = nil) then Exit;

  Lock;
  try
    // 从已使用内存块列表中移除内存块
    if (FUsedMemoryBlockList.Extract(P) = nil) then Exit;

    // 如果最大空闲内存块没有超标，将内存块放到空闲内存块列表中
    if (FFreeMemoryBlockList.Count < FMaxFreeBlocks) then
      FFreeMemoryBlockList.Add(P)
    // 否则释放内存
    else
    begin
      {$IFDEF __HEAP_ALLOC__}
      HeapFree(FHeapHandle, 0, P);
      {$ELSE}
      GlobalFree(HGLOBAL(P));
      {$ENDIF}
      Release;
    end;

    P := nil;
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.Clear;
var
  P: Pointer;
begin
  Lock;
  try
    // 清空空闲内存
    while (FFreeMemoryBlockList.Count > 0) do
    begin
      P := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      if (P <> nil) then
        {$IFDEF __HEAP_ALLOC__}
        HeapFree(FHeapHandle, 0, P);
        {$ELSE}
        GlobalFree(HGLOBAL(P));
        {$ENDIF}
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
      Release;
    end;

    // 清空已使用内存
    while (FUsedMemoryBlockList.Count > 0) do
    begin
      P := FUsedMemoryBlockList[FUsedMemoryBlockList.Count - 1];
      if (P <> nil) then
        {$IFDEF __HEAP_ALLOC__}
        HeapFree(FHeapHandle, 0, P);
        {$ELSE}
        GlobalFree(HGLOBAL(P));
        {$ENDIF}
      FUsedMemoryBlockList.Delete(FUsedMemoryBlockList.Count - 1);
      Release;
    end;
  finally
    Unlock;
  end;
end;

function TIocpMemoryPool.GetFreeBlocks: Integer;
begin
  Result := FFreeMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetFreeBlocksSize: Integer;
begin
  Result := FFreeMemoryBlockList.Count * FBlockSize;
end;

function TIocpMemoryPool.GetUsedBlocks: Integer;
begin
  Result := FUsedMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetUsedBlocksSize: Integer;
begin
  Result := FUsedMemoryBlockList.Count * FBlockSize;
end;

procedure TIocpMemoryPool.SetMaxFreeBlocks(MaxFreeBlocks: Integer);
begin
  Lock;
  FMaxFreeBlocks := MaxFreeBlocks;
  Unlock;
end;

end.
