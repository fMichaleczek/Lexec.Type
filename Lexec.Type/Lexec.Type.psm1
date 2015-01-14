#Requires -Version 5.0.9883.0
#Requires –Modules Poke
Set-StrictMode -Version Latest

class ClassType {
    
    # Input
    [string[]] $ScriptCode = [string]::Empty
    [string[]] $FilePath = [string]::Empty
    [bool] $Passthru = $false
    [System.Management.Automation.Language.ScriptBlockAst] $ScriptBlockAst
    
    [string] $AssemblyName = 'Powershell'
    [version] $AssemblyVersion = [version]'1.0.0'
    [string] $ModuleName = 'PowershellVersion'
    [System.Reflection.Emit.AssemblyBuilderAccess]$AssemblyBuilderAccess = [System.Reflection.Emit.AssemblyBuilderAccess]::Run
    [string] $AssemblyDirectory = $global:ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
    [string] $AssemblyFileName = 'powershell.dll'

    static [PSObject] $Parser
    static [System.AppDomain] $CurrentDomain = [System.AppDomain]::CurrentDomain
    static [System.Reflection.Emit.AssemblyBuilder] $AssemblyBuilder
    static [System.Reflection.Emit.ModuleBuilder] $ModuleBuilder
    static [Type] $xlr8r = [psobject].assembly.gettype("System.Management.Automation.TypeAccelerators")
    
    # Output
    [type[]] $OutputTypes = [type]::EmptyTypes

    hidden Initialize() {
        
        # Get File Content if input is script
        if ([string]::IsNullOrEmpty($this.ScriptCode) -and -not [string]::IsNullOrEmpty($this.FilePath)) {
            foreach($Path in $this.FilePath) {
                if (Test-Path $Path) {
                    $this.ScriptCode += [System.IO.File]::ReadAllText($path)
                }
                else {
                    Write-Warning ( "Path {0} does not exist" -f $Path )
                }
            }
        }
        if ([ClassType]::AssemblyBuilder -eq $null) {
            
            # Assembly Builder and ModuleBuilder
            $Assembly = [System.Reflection.AssemblyName]::new($this.AssemblyName)
            $Assembly.Version = $this.AssemblyVersion
        
            If ($this.AssemblyBuilderAccess -in "Save","RunAndSave" ) {
                [ClassType]::AssemblyBuilder = [ClassType]::CurrentDomain.DefineDynamicAssembly(
                    $Assembly,
                    $this.AssemblyBuilderAccess -as [System.Reflection.Emit.AssemblyBuilderAccess] ,
                    $this.AssemblyDirectory
                )
                [ClassType]::ModuleBuilder = [ClassType]::assemblyBuilder.DefineDynamicModule(
                    $this.ModuleName,
                    $this.AssemblyFileName,
                    $false
                )
            }
            else {
                [ClassType]::AssemblyBuilder = [ClassType]::CurrentDomain.DefineDynamicAssembly($this.AssemblyName,'Run')
                [ClassType]::ModuleBuilder = [ClassType]::AssemblyBuilder.DefineDynamicModule($this.ModuleName)
            }
        }
       
    }

    
    [System.Type[]] Parse() {
        $results = $null

        # Initialize
        if ([ClassType]::AssemblyBuilder -eq $null) {
            $this.Initialize()
        }

        # Parser
        [ClassType]::Parser = (New-TypeProxy 'System.Management.Automation.Language.Parser').__CreateInstance()
        [System.Collections.Generic.List[System.Management.Automation.Language.Token]] $tokenList = @()
        [System.Management.Automation.Language.ParseError[]] $parseErrors = @()
    
        # ScriptBlock Ast
        $this.scriptBlockAst = [ClassType]::Parser.Parse(
            $null, 
            $this.ScriptCode -As [string], 
            $TokenList, 
            $ParseErrors
        )

        (New-ObjectProxy -InputObject $this.ScriptblockAst).ImplementingAssembly = [ClassType]::AssemblyBuilder

        # Browse Type Definition List
        $typeDefinitionList = $this.scriptBlockAst.FindAll({$args[0] -is [System.Management.Automation.Language.TypeDefinitionAst]}, $False)
        
        foreach ($typeDefinitionAst in $typeDefinitionList) {
            Write-Verbose ( "Parse typeDefinitionAst {0}" -f $typeDefinitionAst.Name )
            
            $Type = $this.ParseTypeDefinitionAst($typeDefinitionAst)
            if ($Type) {
                $this.OutputTypes += $Type
            }
        }

        if ($this.AssemblyBuilderAccess -band "Save") {
            [void] [ClassType]::AssemblyBuilder.Save($this.AssemblyFileName)
        }
        
        if ($This.PassThru) {
            $results = $this.OutputTypes
        }

        return $results
    }


    [System.Type] ParseTypeDefinitionAst([System.Management.Automation.Language.TypeDefinitionAst]$TypeDefinitionAst) {
        
        $Type = $null

        [string] $NamespaceName = [string]::Empty
        [type] $parentType = $null
        [type[]] $interfaces = [type]::EmptyTypes
        
        # Get Attributes
        $NamedArguments = $TypeDefinitionAst.Attributes.NamedArguments
        if ( $NamedArguments ) {
        
            # Parent Type
            $parentTypeArgs = $NamedArguments.Where({$_.ArgumentName -eq 'parentType'})
            if ($parentTypeArgs -and $parentTypeArgs.Argument) {
               $ParentType = $parentTypeArgs.Argument.Value -As [Type]
            }

            # Attribute Interface
            $interfacesArgs = $NamedArguments.Where({$_.ArgumentName -eq 'interface'})
            if ($interfacesArgs -ne $null -and $interfacesArgs.Argument -and $interfacesArgs.Argument.Tostring().Split(',').Count -gt 1) {
                   $interfaces = $interfacesArgs.Argument.Tostring().Replace("'","").Replace("(","").Replace(")","").Split(',').Foreach({$_ -As [type]}) -As [type[]]
            }
            elseif($interfacesArgs -ne $null ) {
                $interfaces = @( $interfacesArgs.Argument.Value -As [Type] )
            }
            
            # Attribute NamespaceName and ClassName
            $NamespaceNameArgs = $NamedArguments.Where({$_.ArgumentName -eq 'namespace'})
            if ($NamespaceNameArgs) {
                $NamespaceName = $NamespaceNameArgs.Argument.Value.Tostring()
            }
        }
       
        $className = $typeDefinitionAst.Name
        $staticClassName = "{0}<staticHelpers>" -f $typeDefinitionAst.Name
        if (-not [string]::IsNullOrEmpty($NamespaceName)) {
            $className = "{0}.{1}" -f $NamespaceName,$className
            $staticClassName = "{0}.{1}" -f $NamespaceName,$staticClassName
        }

        #Write-Verbose ( "Class : {0} ParentType : {1} Interfaces : {2}" -f $className, $parentType, $interfaces )

        # We need a dummy ModuleBuilder (in a dummy AssemblyBuilder) to initialize the defineTypeHelper
        # DefineTypeHelper defines the type in the constructor, but we need to call an alternate DefineType 
        $DummyAssemblyBuilder = [ClassType]::CurrentDomain.DefineDynamicAssembly([System.Reflection.AssemblyName]::new('DummyAssembly'),[System.Reflection.Emit.AssemblyBuilderAccess]::Run)
        $DummyModuleBuilder = $DummyAssemblyBuilder.DefineDynamicModule('DummyModule')
        $defineTypeHelper = (New-TypeProxy 'System.Management.Automation.Language.TypeDefiner+DefineTypeHelper').__CreateInstance(
            [System.Management.Automation.Language.Parser]$([ClassType]::Parser.__GetBaseObject()),
            [System.Reflection.Emit.ModuleBuilder]$DummyModuleBuilder,
            [System.Management.Automation.Language.TypeDefinitionAst]$typeDefinitionAst,
            [string]$ClassName
        )
        $DummyModuleBuilder = $null
        $DummyAssemblyBuilder = $null
        
        # Hacking DefineTypeHelper:
        # Replace the dummy module builder, and call DefineType with support for BaseType and Interfaces
        $defineTypeHelper._ModuleBuilder = [ClassType]::ModuleBuilder
       
        # Define Type
        if ($Interfaces -ne $null) {
            $defineTypeHelper._typeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                $className, 
                [System.Reflection.TypeAttributes]'Public', 
                $ParentType, 
                $Interfaces
           )
        }
        elseif($parentType -ne $null) {
            $defineTypeHelper._typeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                $className, 
                [System.Reflection.TypeAttributes]'Public',
                $ParentType
            )
        }
        else {
            $defineTypeHelper._typeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
                $className, 
                [System.Reflection.TypeAttributes]'Public'
            )
        }

        $defineTypeHelper._staticHelpersTypeBuilder = $defineTypeHelper._ModuleBuilder.DefineType(
            $staticClassName, 
            [System.Reflection.TypeAttributes]"NotPublic"
        )
          
        # Create Members
        $defineTypeHelper.DefineMembers()
      
        # Create TypeInfo
        $Type = $defineTypeHelper._typeBuilder.CreateTypeInfo()
        $TypeStatic = $defineTypeHelper._staticHelpersTypeBuilder.CreateTypeInfo()

        # Update ScriptBlockMemberMethodWrapper Field , only work with AssemblyBuilderAccess set to Run or RunAndSave
        if ($defineTypeHelper._fieldsToInitForMemberFunctions -ne $null) {
            foreach ($tuple in $defineTypeHelper._fieldsToInitForMemberFunctions) {
                $Field = $defineTypeHelper._staticHelpersTypeBuilder.GetField([string]$tuple.Item1,[System.Reflection.BindingFlags]"Static,NonPublic")
                $Field.SetValue([System.Management.Automation.Internal.AutomationNull]::Value, [System.Management.Automation.ScriptBlockMemberMethodWrapper]$tuple.Item2)
            }
        }
            
        # Create Type
        [void] $defineTypeHelper._typeBuilder.CreateType()
        [void] $defineTypeHelper._staticHelpersTypeBuilder.CreateType()
        $defineTypeHelper = $null
        
        # Add Accelerator
        [void] [ClassType]::xlr8r::Remove($ClassName)
        [void] [ClassType]::xlr8r::Add($ClassName, $Type)
        
        # Return Type
        return $Type
    }

}
function Add-ClassType {
    [OutputType([Type[]])]
    [CmdletBinding(DefaultParameterSetName='Code')]
    Param(
        [Parameter(Mandatory=$true,ParameterSetName="Code",Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("Script","Code")]
        [string[]] 
        $ScriptCode,
        
        [Parameter(Mandatory=$true,ParameterSetName="File",Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("File","Path")]
        [string[]]
        $FilePath,
        
        [Parameter()]
        [switch]
        $PassThru,

        [Parameter()]
        [ValidateSet('Run','RunAndSave','Save')]
        [Alias("BuilderAccess","Access")]
        [System.Reflection.Emit.AssemblyBuilderAccess]
        $AssemblyBuilderAccess ,

        [Parameter()]
        [string]
        $AssemblyPath,
        
        [Parameter()]
        [string]
        $AssemblyName,

        [Parameter()]
        [string]
        $ModuleName,
        
        [Parameter()]
        [version]
        $AssemblyVersion

    )
    $Types = [type]::EmptyTypes
    $ClassType = [ClassType]$PSBoundParameters
    $Types = $ClassType.Parse()
    return $Types
}

$ExecutionContext.SessionState.Module.OnRemove = {
    
}

Export-ModuleMember -Function Add-ClassType