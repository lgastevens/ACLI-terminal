'Version = 1.01
If WScript.Arguments.Count >= 1 Then
    ReDim arr(WScript.Arguments.Count-1)
    For i = 0 To WScript.Arguments.Count-1
        Arg = WScript.Arguments(i)
        Arg = Replace(Arg, Chr(250), Chr(163)) 'Hack to preserve pound sign '£' which otherwise comes out as 'ú'
        If InStr(Arg, " ") > 0 Or InStr(Arg, ":") > 0 Then Arg = """" & Arg & """"
        arr(i) = Arg
    Next
    Args = Join(arr)
    'MsgBox (Args)
End If
RunCmd = "cmd /c acligui.bat " & Args
CreateObject("Wscript.Shell").Run RunCmd, 0, True
