Lexec.Type
===========

Module about Powershell, Class, AssemblyBuilder and DotNet Type

EXPERIMENTAL (IN ACTIVE DEVELOPMENT)

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

Requires -Version 5.0.9883.0

Requires –Modules Poke

Example :
---------

# Example with attributes MetaClassAttribute
```powershell
Add-ClassType {
    [MetaClassAttribute('MyNamespace',[Object],[System.Collections.IEnumerable])]
    class EnumeratedGreeting1 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
    [MetaClassAttribute('MyNamespace2',[Object],[System.Collections.IEnumerable])]
    class EnumeratedGreeting2 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
} -PassThru | Select FullName,Name
```

# Example with attributes MetaClassAttribute
```powershell
Add-ClassType {
    [MetaClassAttribute('MyNamespace',[Object],[System.Collections.IEnumerable])]
    class EnumeratedGreeting1 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
    [MetaClassAttribute(BaseType = [Object], Interfaces=[System.Collections.IEnumerable])]
    class EnumeratedGreeting2 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
    [MetaClassAttribute(NameSpaceName='Something.Wicked', BaseType = [Object], Interfaces=([System.Collections.IEnumerable],[System.Collections.IList]))]
    class EnumeratedGreeting3 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
    
} -PassThru | Select FullName,Name

# Example where we use AST keyword namespace
```powershell
Add-ClassType {
    namespace toto {
        [MetaClassAttribute('AAA',[Object],[System.Collections.IEnumerable])]
        class EnumeratedGreeting3 {
            [System.Collections.IEnumerator] GetEnumerator() {
                return "Hello World".GetEnumerator()
            }
        }
    }
} -PassThru | Select FullName,Name
```

# Example with cmdlet namespace contain classes
```powershell
$Files = Get-ChildItem -File -Path "C:\Projects\PowershellClass" -Filter "*.ps1" 
Add-ClassType -Namespace Titi -FilePath $Files.FullName -PassThru | Select FullName,Name
```

# Example where we alias namespace to change Add-ClassType behaviour
```powershell
Set-Alias namespace Add-ClassType
Set-Alias %namespace Add-ClassType

& namespace toto {
    [MetaClassAttribute('ttttt',[Object],[System.Collections.IEnumerable])]
    class EnumeratedGreeting4 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
} -PassThru | Select FullName,Name

%namespace toto {
    [MetaClassAttribute('aaaaa',[Object],[System.Collections.IEnumerable])]
    class EnumeratedGreeting5 {
        [System.Collections.IEnumerator] GetEnumerator() {
            return "Hello World".GetEnumerator()
        }
    }
} -PassThru | Select FullName,Name
```

# Example with an simple interface and debug export to dll
```powershell
Add-Type -Language Csharp -TypeDefinition @'
    public interface IFoo
    {
        void Foo();
    }
'@ 
Add-ClassType -BuilderAccess 'RunAndSave' {
    [MetaClassAttribute(NamespaceName='MyNameSpaceTest.SubName',BaseType=[object],Interfaces=[IFoo])]
        class ClassImplementsInterface {
            [string] $Name

            ClassImplementsInterface($Name) {
                $this.Name = $Name
            }
            [void] Foo() {
                Write-Host "Foo()"
            }
        }
}
[MyNameSpaceTest.SubName.ClassImplementsInterface]::new('toto') -is [iFoo]
```

Flavien Michaleczek
fmichaleczek@gmail.com
https://twitter.com/_Flavien
