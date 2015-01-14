Lexec.Type
===========

Module about Powershell and DotNet Type

EXPERIMENTAL

About this module :
-------------------

- This script is a proof of concept about AssemblyBuilder, Expression, AST and CLR Class
- It uses method System.Management.Automation.Language.TypeDefiner that is a class in active development in Powershell 5.0 Preview.
- ParentType needs improvements
- Dll can not be load, it is only for reflection and debugging
- If you change AssemblyBuilderAccess to "Save" only, you will notice errors about SetValue to Field in the static Class helpers
  IronPython and DLR use a object ScriptCodeOnDisk that parse Lambda Expression and invoke a special method CompileToMethod() to push a DLRCache into an assembly

Requirements :
-------------

#Requires -Version 5.0.9883.0
#Requires –Modules Poke

Example :
---------

```powershell

Add-Type -Language Csharp -TypeDefinition @'
    public interface IFoo
    {
        void Foo();
    }
'@ 

Add-ClassType -BuilderAccess 'RunAndSave' -ScriptCode @'
[SuperClass(namespace='MyNameSpaceTest.SubName',interface='IFoo')]
    class ClassImplementsInterface {
        [string] $Name

        ClassImplementsInterface($Name) {
            $this.Name = $Name
        }
        [void] Foo() {
            Write-Host "Foo()"
        }
    }
'@

[MyNameSpaceTest.SubName
```


Flavien Michaleczek
fmichaleczek@gmail.com
https://twitter.com/_Flavien
