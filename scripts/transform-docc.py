#!/usr/bin/env python3

"""
PostHog iOS SDK DocC Documentation Transformer

Transforms DocC-generated documentation directory into the format required by the PostHog documentation website.
This version parses the individual JSON files in the DocC data directory structure.
"""

import json
import sys
import os
import re
from typing import Dict, List, Any, Optional
from pathlib import Path

def categorize_method(method_name: str, class_name: str = "") -> str:
    """Categorize methods based on their names and functionality."""
    
    # Initialization methods
    if method_name in ["setup", "with"] or "init" in method_name.lower():
        return "Initialization"
    
    # Identification methods  
    if method_name in ["identify", "alias", "getDistinctId", "getAnonymousId"]:
        return "Identification"
    
    # Capture methods
    if method_name in ["capture", "screen", "autocapture", "flush", "register", "unregister"]:
        return "Capture"
    
    # Feature flag methods
    if any(flag_term in method_name.lower() for flag_term in ["feature", "flag", "reload"]):
        return "Feature flags"
    
    # Session replay methods
    if any(replay_term in method_name.lower() for replay_term in ["session", "recording", "replay"]):
        return "Session replay"
    
    # Privacy methods
    if method_name in ["optOut", "optIn", "reset", "isOptOut"]:
        return "Privacy"
    
    # Configuration methods
    if method_name in ["debug", "close"] or method_name.startswith("get"):
        return "Configuration"
    
    # Default fallback
    return "Configuration"


def extract_parameters_from_docc(method_data: Dict, declaration_fragments: List[Dict] = None, method_title: str = "") -> List[Dict]:
    """Extract parameters from DocC method data according to DocC format standards."""
    params = []
    
    # First try to get parameters from DocC primaryContentSections (preferred)
    docc_parameters = []
    primary_sections = method_data.get("primaryContentSections", [])
    for section in primary_sections:
        if section.get("kind") == "parameters":
            docc_parameters = section.get("parameters", [])
            print(f"    Found DocC parameters section: {docc_parameters}")
            break
    if docc_parameters:
        for param in docc_parameters:
            param_name = param.get("name", "")
            param_description = ""
            
            # Extract description from content array (DocC format)
            content = param.get("content", [])
            if content and isinstance(content, list):
                description_parts = []
                for item in content:
                    if isinstance(item, dict):
                        # Check for inlineContent structure
                        inline_content = item.get("inlineContent", [])
                        if inline_content:
                            for inline_item in inline_content:
                                if isinstance(inline_item, dict) and inline_item.get("type") == "text":
                                    description_parts.append(inline_item.get("text", ""))
                        # Fallback to direct text
                        elif item.get("text"):
                            description_parts.append(item.get("text", ""))
                param_description = " ".join(description_parts)
                print(f"    Extracted param description for '{param_name}': '{param_description}'")
            
            # Extract type from declaration fragments if available
            param_type = "Any"
            if declaration_fragments:
                param_type = extract_parameter_type_from_fragments(declaration_fragments, param_name)
            
            params.append({
                "name": param_name,
                "type": param_type,
                "description": param_description,
                "isOptional": "?" in param_type
            })
        return params
    
    # Fallback: extract from declaration fragments
    if declaration_fragments:
        return extract_parameters_from_declaration_fragments(declaration_fragments, method_title)
    
    return params

def extract_parameter_type_from_fragments(declaration_fragments: List[Dict], param_name: str) -> str:
    """Extract parameter type from declaration fragments for a specific parameter."""
    # Look for parameter name followed by type in fragments
    found_param = False
    for i, fragment in enumerate(declaration_fragments):
        text = fragment.get("text", "")
        kind = fragment.get("kind", "")
        
        if text == param_name and kind == "externalParam":
            found_param = True
        elif found_param and kind == "typeIdentifier":
            return text
    
    return "Any"

def extract_parameters_from_declaration_fragments(declaration_fragments: List[Dict], method_title: str = "") -> List[Dict]:
    """Extract parameters from DocC declaration fragments (fallback method)."""
    params = []
    
    # Look for parameter patterns in declaration fragments
    in_params = False
    param_index = 0
    current_param_name = None
    
    for i, fragment in enumerate(declaration_fragments):
        text = fragment.get("text", "")
        kind = fragment.get("kind", "")
        
        if text == "(":
            in_params = True
            continue
        elif text == ")":
            break
        elif not in_params:
            continue
        elif kind == "externalParam":
            current_param_name = text
        elif kind == "typeIdentifier" and current_param_name:
            params.append({
                "name": current_param_name,
                "type": text,
                "description": f"The {current_param_name} parameter",
                "isOptional": "?" in text
            })
            current_param_name = None
            param_index += 1
        elif kind == "typeIdentifier" and not current_param_name:
            # Unnamed parameter
            param_name = infer_parameter_name(method_title, param_index)
            params.append({
                "name": param_name,
                "type": text,
                "description": f"The {param_name} parameter",
                "isOptional": "?" in text
            })
            param_index += 1
    
    return params

def infer_parameter_name(method_title: str, param_index: int) -> str:
    """Infer parameter name from method title and index."""
    if not method_title:
        return f"param{param_index}"
    
    base_method_name = method_title.split("(")[0] if "(" in method_title else method_title
    
    # Common parameter name patterns
    if "alias" in base_method_name.lower():
        return "alias"
    elif "identify" in base_method_name.lower():
        return "distinctId"
    elif "capture" in base_method_name.lower():
        return "event" if param_index == 0 else "properties"
    elif "screen" in base_method_name.lower():
        return "name" if param_index == 0 else "properties"
    elif "group" in base_method_name.lower():
        return "type" if param_index == 0 else "key"
    else:
        return f"param{param_index}"

def extract_property_type_from_fragments(fragments: List[Dict]) -> str:
    """Extract property type from declaration fragments, handling complex types."""
    if not fragments:
        return "Any"
    
    # Reconstruct the full type from fragments
    type_parts = []
    skip_until_colon = True
    
    for fragment in fragments:
        text = fragment.get("text", "")
        kind = fragment.get("kind", "")
        
        # Skip until we find the colon (which separates property name from type)
        if skip_until_colon:
            if text == ":":
                skip_until_colon = False
            continue
        
        # Collect type-related fragments
        if kind == "typeIdentifier":
            type_parts.append(text)
        elif kind == "identifier" and text and (text[0].isupper() or text in ["string", "number", "boolean", "null", "undefined"]):
            type_parts.append(text)
        elif text in ["?", "!", "[", "]", "|", "<", ">", ",", "(", ")", " "]:
            type_parts.append(text)
        elif text and text.strip() and text not in ["=", "var", "let", ":"]:
            # Include other relevant text
            if not type_parts or text != type_parts[-1]:  # Avoid duplicates
                type_parts.append(text)
    
    if type_parts:
        # Join the type parts
        prop_type = "".join(type_parts).strip()
        
        # Convert Swift Optional syntax to TypeScript-like (String? -> string | null)
        if prop_type.endswith("?"):
            base_type = prop_type[:-1].strip()
            # Map Swift types to TypeScript-like
            swift_to_ts = {
                "String": "string",
                "Int": "number",
                "Double": "number",
                "Float": "number",
                "Bool": "boolean",
            }
            base_type_ts = swift_to_ts.get(base_type, base_type)
            prop_type = f"{base_type_ts} | null"
        # Convert Swift Array syntax to TypeScript-like
        elif prop_type.startswith("[") and "]" in prop_type:
            # Handle [String] syntax
            inner_match = re.search(r'\[(.+?)\]', prop_type)
            if inner_match:
                inner_type = inner_match.group(1).strip()
                swift_to_ts = {
                    "String": "string",
                    "Int": "number",
                    "Bool": "boolean",
                }
                inner_type_ts = swift_to_ts.get(inner_type, inner_type)
                prop_type = f"{inner_type_ts}[]"
        # Convert basic Swift types
        else:
            swift_to_ts = {
                "String": "string",
                "Int": "number",
                "Double": "number",
                "Float": "number",
                "Bool": "boolean",
            }
            if prop_type in swift_to_ts:
                prop_type = swift_to_ts[prop_type]
        
        return prop_type
    
    # Fallback: look for any identifier that might be a type
    for fragment in fragments:
        text = fragment.get("text", "")
        kind = fragment.get("kind", "")
        if kind in ["identifier", "typeIdentifier"] and text and text[0].isupper():
            return text
    
    return "Any"

def extract_enum_cases_from_docc(type_data: Dict, references: Dict, docc_data_dir: str) -> List[Dict]:
    """Extract enum cases from DocC type data."""
    enum_cases = []
    
    # Look for topicSections which contain enum cases
    topic_sections = type_data.get("topicSections", [])
    
    # Find the "Enumeration Cases" section
    for section in topic_sections:
        section_title = section.get("title", "")
        identifiers = section.get("identifiers", [])
        
        # Look for the "Enumeration Cases" section
        if section_title == "Enumeration Cases" and identifiers:
            print(f"        Found Enumeration Cases section with {len(identifiers)} cases")
            
            for case_id in identifiers:
                case_ref = references.get(case_id, {})
                if not case_ref:
                    continue
                
                # Extract case name from title (format: "EnumName.caseName")
                case_title = case_ref.get("title", "")
                fragments = case_ref.get("fragments", [])
                
                # Extract case name from fragments (look for identifier after "case" keyword)
                case_name = None
                if fragments:
                    found_case_keyword = False
                    for fragment in fragments:
                        if fragment.get("kind") == "keyword" and fragment.get("text") == "case":
                            found_case_keyword = True
                        elif found_case_keyword and fragment.get("kind") == "identifier":
                            case_name = fragment.get("text")
                            break
                
                # Fallback: extract from title (remove enum prefix)
                if not case_name and case_title:
                    if "." in case_title:
                        case_name = case_title.split(".")[-1]
                    else:
                        case_name = case_title
                
                if case_name:
                    print(f"          Found enum case: {case_name}")
                    
                    # Extract enum case description
                    case_abstract = case_ref.get("abstract", [])
                    case_description = ""
                    if case_abstract and isinstance(case_abstract, list):
                        case_description = " ".join([item.get("text", "") for item in case_abstract if isinstance(item, dict)])
                    elif isinstance(case_abstract, str):
                        case_description = case_abstract
                    
                    # Try to load individual enum case file for detailed documentation
                    if case_id.startswith("doc://"):
                        # Convert doc URL to file path
                        # doc://PostHog/documentation/PostHog/PostHogSurveyResponseType/link
                        # -> posthog/posthogsurveyresponsetype/link.json
                        # Remove the doc://PostHog/documentation/PostHog/ prefix
                        case_path = case_id.replace("doc://PostHog/documentation/PostHog/", "")
                        # Convert to lowercase and build path (prepend posthog/ since that's the directory structure)
                        case_path_parts = ["posthog"] + [part.lower() for part in case_path.split("/") if part]
                        case_file_path = os.path.join(docc_data_dir, *case_path_parts) + ".json"
                        
                        if os.path.exists(case_file_path):
                            try:
                                with open(case_file_path, 'r', encoding='utf-8') as f:
                                    case_data = json.load(f)
                                    
                                # Look for detailed description in primaryContentSections
                                primary_sections = case_data.get("primaryContentSections", [])
                                for section in primary_sections:
                                    if section.get("kind") == "content":
                                        content_items = section.get("content", [])
                                        description_parts = []
                                        for item in content_items:
                                            if isinstance(item, dict) and item.get("type") == "paragraph":
                                                inline_content = item.get("inlineContent", [])
                                                for inline_item in inline_content:
                                                    if isinstance(inline_item, dict) and inline_item.get("type") == "text":
                                                        description_parts.append(inline_item.get("text", ""))
                                        if description_parts:
                                            case_description = " ".join(description_parts)
                                            break
                            except Exception as e:
                                print(f"          Error loading enum case file {case_file_path}: {e}")
                    
                    # Build enum case object
                    case_obj = {
                        "name": case_name
                    }
                    
                    # Only add description if it exists
                    if case_description:
                        case_obj["description"] = case_description
                    
                    enum_cases.append(case_obj)
    
    print(f"        Extracted {len(enum_cases)} enum cases")
    return enum_cases

def extract_properties_from_docc(type_data: Dict, references: Dict, docc_data_dir: str) -> List[Dict]:
    """Extract properties from DocC type data."""
    properties = []
    
    # Look for topicSections which contain properties
    topic_sections = type_data.get("topicSections", [])
    for section in topic_sections:
        section_title = section.get("title", "")
        identifiers = section.get("identifiers", [])
        
        # Look for property-related sections
        if section_title and identifiers:
            # Check if this section contains properties (not methods)
            for prop_id in identifiers:
                prop_ref = references.get(prop_id, {})
                if not prop_ref:
                    continue
                
                prop_kind = prop_ref.get("kind", "")
                prop_title = prop_ref.get("title", "")
                
                # Skip methods, initializers, enum cases, etc.
                # Only include properties (var, let) and associated values
                if any(kind in prop_kind for kind in ["method", "initializer", "func", "enum.case", "subscript"]):
                    continue
                
                # Check if this is actually a property (has fragments that suggest a property declaration)
                fragments = prop_ref.get("fragments", [])
                has_property_indicators = False
                for frag in fragments:
                    frag_text = frag.get("text", "")
                    if frag_text in ["var", "let"] or ":" in frag_text:
                        has_property_indicators = True
                        break
                
                # If no property indicators and it's not a type, skip it
                if not has_property_indicators and "property" not in prop_kind.lower():
                    continue
                
                # This should be a property
                print(f"        Property: {prop_title}")
                
                # Extract property type from fragments
                prop_type = extract_property_type_from_fragments(fragments)
                
                # Extract property description
                prop_abstract = prop_ref.get("abstract", [])
                prop_description = ""
                if prop_abstract and isinstance(prop_abstract, list):
                    prop_description = " ".join([item.get("text", "") for item in prop_abstract if isinstance(item, dict)])
                elif isinstance(prop_abstract, str):
                    prop_description = prop_abstract
                
                # Try to load individual property file for detailed documentation
                if prop_id.startswith("doc://"):
                    prop_path = prop_id.replace("doc://PostHog/documentation/", "").replace("/", "/").lower()
                    prop_file_path = os.path.join(docc_data_dir, prop_path + ".json")
                    
                    if os.path.exists(prop_file_path):
                        try:
                            with open(prop_file_path, 'r', encoding='utf-8') as f:
                                prop_data = json.load(f)
                                
                            # Look for detailed description in primaryContentSections
                            primary_sections = prop_data.get("primaryContentSections", [])
                            for section in primary_sections:
                                if section.get("kind") == "content":
                                    content_items = section.get("content", [])
                                    description_parts = []
                                    for item in content_items:
                                        if isinstance(item, dict) and item.get("type") == "paragraph":
                                            inline_content = item.get("inlineContent", [])
                                            for inline_item in inline_content:
                                                if isinstance(inline_item, dict) and inline_item.get("type") == "text":
                                                    description_parts.append(inline_item.get("text", ""))
                                    if description_parts:
                                        prop_description = " ".join(description_parts)
                                        break
                        except Exception as e:
                            print(f"          Error loading property file {prop_file_path}: {e}")
                
                # Build property object
                prop_obj = {
                    "type": prop_type,
                    "name": prop_title
                }
                
                # Only add description if it exists
                if prop_description:
                    prop_obj["description"] = prop_description
                
                properties.append(prop_obj)
    
    return properties

def parse_class_json(class_file_path: str) -> Dict:
    """Parse a DocC class JSON file to extract methods and details."""
    
    try:
        with open(class_file_path, 'r') as f:
            class_data = json.load(f)
    except Exception as e:
        print(f"❌ Error reading {class_file_path}: {e}")
        return {}
    
    class_info = {
        "functions": []
    }
    
    # Extract class description
    abstract = class_data.get("abstract", [])
    if abstract and isinstance(abstract, list):
        description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
        class_info["description"] = description
    
    # Look for relationships to find methods
    relationships = class_data.get("relationships", {})
    
    # Check for memberOf relationships (methods belonging to this class)
    members = relationships.get("memberOf", [])
    
    for member in members:
        member_title = member.get("title", "")
        member_kind = member.get("kind", "")
        
        if any(method_kind in member_kind for method_kind in ["method", "initializer", "func"]):
            # Extract method details
            method_name = member_title
            category = categorize_method(method_name)
            
            # Extract parameters from declaration if available
            params = []
            declaration = member.get("declaration", {})
            if declaration and "declarationFragments" in declaration:
                params = extract_parameters_from_declaration_fragments(declaration["declarationFragments"], method_name)
            
            method_info = {
                "category": category,
                "description": member.get("abstract", {}).get("text", f"{method_name} method"),
                "id": method_name,
                "showDocs": True,
                "title": method_name,
                "releaseTag": "public",
                "params": params,
                "returnType": {
                    "id": "Void",
                    "name": "Void"
                },
                "path": f"PostHog/{class_info.get('title', 'Unknown')}.swift"
            }
            
            # Only add details if there's actual discussion content
            discussion = member.get("discussion", {})
            if discussion and discussion.get("content"):
                details_text = discussion.get("content", [{}])[0].get("text", "")
                if details_text:
                    method_info["details"] = details_text
            
            class_info["functions"].append(method_info)
    
    return class_info

def is_internal_class(title: str) -> bool:
    """Check if a class should be filtered out as internal."""
    known_internal_classes = [
        "PostHogStorageManager"
    ]
    return title in known_internal_classes

def process_docc_directory(docc_data_dir: str, version: str) -> Dict:
    """Process the entire DocC data directory structure."""
    
    result = {
        "id": "posthog-ios",
        "hogRef": "0.3",
        "info": {
            "version": version,
            "id": "posthog-ios", 
            "title": "PostHog iOS SDK",
            "description": "PostHog iOS SDK allows you to automatically capture usage and send events to PostHog from iOS applications.",
            "slugPrefix": "posthog-ios",
            "specUrl": "https://github.com/PostHog/posthog-ios"
        },
        "classes": [],
        "types": [],
        "categories": [
            "Initialization",
            "Identification", 
            "Capture",
            "Feature flags",
            "Session replay",
            "Privacy",
            "Configuration"
        ]
    }
    
    classes = {}
    types = {}
    
    # Find PostHog-related JSON files
    docc_path = Path(docc_data_dir)
    posthog_dir = docc_path / "posthog"
    
    if not posthog_dir.exists():
        print(f"❌ PostHog directory not found in {docc_data_dir}")
        return result
    
    print(f"📊 Processing DocC directory: {posthog_dir}")
    
    # Process all JSON files in the posthog directory
    for json_file in posthog_dir.glob("**/*.json"):
        file_name = json_file.stem
        
        # Skip non-PostHog files
        if not any(term in file_name.lower() for term in ["posthog"]):
            continue
            
        print(f"🔍 Processing file: {json_file.name}")
        
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
        except Exception as e:
            print(f"❌ Error reading {json_file}: {e}")
            continue
        
        # Extract basic info with better error handling
        try:
            metadata = data.get("metadata", {})
            if isinstance(metadata, dict):
                title = metadata.get("title", file_name)
            else:
                title = file_name
                
            kind_data = data.get("kind", {})
            if isinstance(kind_data, dict):
                kind = kind_data.get("identifier", "")
            else:
                kind = str(kind_data) if kind_data else ""
        except Exception as e:
            print(f"❌ Error extracting metadata from {json_file}: {e}")
            print(f"   Data keys: {list(data.keys()) if isinstance(data, dict) else 'Not a dict'}")
            continue
        
        print(f"  📝 Found: {title} ({kind})")
        
        # Handle classes - DocC uses 'symbol' as kind, check metadata for actual type
        metadata = data.get("metadata", {})
        symbol_kind = metadata.get("symbolKind", "")
        
        if (kind == "symbol" and symbol_kind == "class" and "PostHog" in title):
            # Filter out internal classes
            if is_internal_class(title):
                print(f"  ⏭️  Skipping internal class: {title}")
                continue
            
            # Special case: PostHogConfig should be in types, not classes
            if title == "PostHogConfig":
                # Add PostHogConfig to types with example
                abstract = data.get("abstract", [])
                description = ""
                if abstract and isinstance(abstract, list):
                    description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
                elif isinstance(abstract, str):
                    description = abstract
                
                references = data.get("references", {})
                example = generate_posthog_config_example(data, references, docc_data_dir)
                
                types[title] = {
                    "id": title,
                    "name": title,
                    "properties": [],
                    "path": f"PostHog/{title}.swift",
                    "example": example
                }
                continue  # Skip processing as a class
            
            if title not in classes:
                # Extract description
                abstract = data.get("abstract", [])
                description = ""
                if abstract and isinstance(abstract, list):
                    description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
                elif isinstance(abstract, str):
                    description = abstract
                
                classes[title] = {
                    "description": description or f"The {title} class",
                    "id": title,
                    "title": title,
                    "functions": []
                }
                
                # Look for topicSections which contain methods
                topic_sections = data.get("topicSections", [])
                for section in topic_sections:
                    section_title = section.get("title", "")
                    print(f"    Processing section: {section_title}")
                    
                    # Process all sections: methods, properties, initializers, etc.
                    if section_title and section.get("identifiers"):
                        identifiers = section.get("identifiers", [])
                        print(f"      Found {len(identifiers)} methods")
                        
                        for method_id in identifiers:
                            # Look up method details in references
                            references = data.get("references", {})
                            method_ref = references.get(method_id, {})
                            
                            if method_ref:
                                method_title = method_ref.get("title", "")
                                method_kind = method_ref.get("kind", "")
                                
                                print(f"        Method: {method_title}")
                                
                                # Clean up method name (remove Swift syntax like (_:))
                                clean_method_name = method_title.split("(")[0] if "(" in method_title else method_title
                                
                                # Extract method details
                                category = categorize_method(clean_method_name, title)
                                
                                # Extract parameters using DocC format standards
                                params = []
                                fragments = method_ref.get("fragments", [])
                                print(f"          Fragments: {fragments[:5]}...")  # Show first 5 fragments
                                
                                # Load individual method file for detailed parameter documentation
                                method_data = {}
                                if method_id.startswith("doc://"):
                                    # Convert doc URL to file path
                                    method_path = method_id.replace("doc://PostHog/documentation/", "").replace("/", "/").lower()
                                    method_file_path = os.path.join(docc_data_dir, method_path + ".json")
                                    
                                    if os.path.exists(method_file_path):
                                        try:
                                            with open(method_file_path, 'r', encoding='utf-8') as f:
                                                method_data = json.load(f)
                                                print(f"          Loaded method file: {method_file_path}")
                                        except Exception as e:
                                            print(f"          Error loading method file {method_file_path}: {e}")
                                
                                params = extract_parameters_from_docc(method_data, fragments, method_title)
                                print(f"          Extracted params: {params}")
                                
                                # Extract description following DocC format
                                method_abstract = method_ref.get("abstract", [])
                                method_description = ""
                                if method_abstract and isinstance(method_abstract, list):
                                    method_description = " ".join([item.get("text", "") for item in method_abstract if isinstance(item, dict)])
                                elif isinstance(method_abstract, str):
                                    method_description = method_abstract
                                
                                # Extract detailed discussion from the loaded method file
                                method_details = method_description  # fallback to description
                                if method_data:
                                    # Look for discussion in primaryContentSections
                                    primary_sections = method_data.get("primaryContentSections", [])
                                    for section in primary_sections:
                                        if section.get("kind") == "content":
                                            content_items = section.get("content", [])
                                            discussion_parts = []
                                            for item in content_items:
                                                if isinstance(item, dict) and item.get("type") == "paragraph":
                                                    inline_content = item.get("inlineContent", [])
                                                    for inline_item in inline_content:
                                                        if isinstance(inline_item, dict) and inline_item.get("type") == "text":
                                                            discussion_parts.append(inline_item.get("text", ""))
                                            if discussion_parts:
                                                method_details = " ".join(discussion_parts)
                                                break
                                
                                # Extract return type from DocC returns section
                                return_type = {"id": "Void", "name": "Void"}
                                method_returns = method_ref.get("returns", {})
                                if method_returns:
                                    return_content = method_returns.get("content", [])
                                    if return_content:
                                        return_description = " ".join([item.get("text", "") for item in return_content if isinstance(item, dict)])
                                        # Try to extract return type from description or fragments
                                        if "Bool" in return_description:
                                            return_type = {"id": "Bool", "name": "Bool"}
                                        elif "String" in return_description:
                                            return_type = {"id": "String", "name": "String"}
                                        # Add more type detection as needed
                                
                                # Extract throws information
                                throws_info = None
                                method_throws = method_ref.get("throws", {})
                                if method_throws:
                                    throws_content = method_throws.get("content", [])
                                    if throws_content:
                                        throws_info = " ".join([item.get("text", "") for item in throws_content if isinstance(item, dict)])
                                
                                method_info = {
                                    "category": category,
                                    "description": method_description or f"{clean_method_name} method",
                                    "id": clean_method_name,
                                    "showDocs": True,
                                    "title": clean_method_name,
                                    "releaseTag": "public",
                                    "params": params,
                                    "returnType": return_type,
                                    "path": f"PostHog/{title}.swift"
                                }
                                
                                # Only add details if there's actual content
                                if method_details:
                                    method_info["details"] = method_details
                                
                                # Add throws information if available
                                if throws_info:
                                    method_info["throws"] = throws_info
                                
                                # Generate examples array
                                examples = generate_method_examples(clean_method_name, params, return_type, title)
                                if examples:
                                    method_info["examples"] = examples
                                
                                classes[title]["functions"].append(method_info)
        
        # Handle enums/structs
        elif (kind == "symbol" and symbol_kind in ["enum", "struct"]):
            abstract = data.get("abstract", [])
            description = ""
            if abstract and isinstance(abstract, list):
                description = " ".join([item.get("text", "") for item in abstract if isinstance(item, dict)])
            elif isinstance(abstract, str):
                description = abstract
            
            # Extract properties or enum cases from DocC data
            references = data.get("references", {})
            enum_cases = []  # Store enum cases for later use in example
            example = None  # Will be set for enums
            
            if symbol_kind == "enum":
                # For enums, extract enum cases but keep properties empty
                enum_cases = extract_enum_cases_from_docc(data, references, docc_data_dir)
                properties = []  # Enums have empty properties
                
                # Generate Swift enum declaration example right here
                enum_cases_for_example = [case["name"] for case in enum_cases] if enum_cases else []
                if enum_cases_for_example:
                    case_lines = "\n    ".join([f"case {case_name}" for case_name in enum_cases_for_example])
                    example = f"enum {title} {{\n    {case_lines}\n}}"
                else:
                    example = f"enum {title} {{\n    // cases\n}}"
            else:
                # For structs, extract properties
                properties = extract_properties_from_docc(data, references, docc_data_dir)
            
            # Build type object
            type_obj = {
                "id": title,
                "name": title,
                "properties": properties,
                "path": f"PostHog/{title}.swift"
            }
            
            # Add example if we generated one (for enums)
            if example:
                type_obj["example"] = example
            # For structs and other types, generate example if no properties
            elif not properties:
                # Look for example in primaryContentSections or discussion
                example = None
                primary_sections = data.get("primaryContentSections", [])
                for section in primary_sections:
                    if section.get("kind") == "content":
                        content_items = section.get("content", [])
                        for item in content_items:
                            if isinstance(item, dict):
                                # Look for code blocks or examples
                                inline_content = item.get("inlineContent", [])
                                for inline_item in inline_content:
                                    if isinstance(inline_item, dict) and inline_item.get("type") == "codeVoice":
                                        example = inline_item.get("text", "")
                                        break
                                if example:
                                    break
                    if example:
                        break
                
                # Default fallback
                if not example:
                    example = f"{title}()"
                
                type_obj["example"] = example
            
            types[title] = type_obj
    
    result["classes"] = list(classes.values())
    result["types"] = list(types.values())
    
    print(f"🔍 Processed DocC documentation")
    print(f"📋 Generated {len(classes)} classes and {len(types)} types")
    
    return result

def get_instance_for_class(class_name: str) -> str:
    if not class_name:
        # Fallback: use generic instance name when class name is unknown
        return "instance"
    
    # Singleton pattern: classes ending with "SDK" typically use .shared
    if class_name.endswith("SDK"):
        return f"{class_name}.shared"
    
    # For all other types, use standard camelCase convention
    if len(class_name) > 1:
        return class_name[0].lower() + class_name[1:]
    return class_name.lower()

def generate_method_examples(method_name: str, params: List[Dict], return_type: Dict, class_name: str = "") -> List[Dict]:
    """Generate examples array with id, name, and code fields."""
    examples = []
    
    # Determine the appropriate instance based on class/type name
    instance = get_instance_for_class(class_name)
    
    if not params:
        # No parameters - simple example
        code = f"{instance}.{method_name}()"
        examples.append({
            "id": f"basic_{method_name}",
            "name": f"Basic {method_name}",
            "code": code
        })
    else:
        # Build example with parameter values
        param_parts = []
        for param in params:
            param_name = param.get("name", "")
            param_type = param.get("type", "Any")
            # Generate placeholder value based on type
            if "String" in param_type:
                placeholder = f'"{param_name}_value"'
            elif "Int" in param_type or "Double" in param_type or "Float" in param_type:
                placeholder = "0"
            elif "Bool" in param_type:
                placeholder = "true"
            elif "[" in param_type:  # Array
                placeholder = "[]"
            else:
                placeholder = f'"{param_name}_value"'
            param_parts.append(f"{param_name}: {placeholder}")
        
        params_str = ", ".join(param_parts)
        code = f"{instance}.{method_name}({params_str})"
        examples.append({
            "id": f"basic_{method_name}",
            "name": f"Basic {method_name}",
            "code": code
        })
    
    return examples

def generate_posthog_config_example(class_data: Dict, references: Dict, docc_data_dir: str) -> str:
    """
    Generate example code for PostHogConfig initialization and setup.

    TODO: DocC can't generate for iOS-only properties. 
    We need to manually add them to the example in the future
    """
    init_line = "let config = PostHogConfig(apiKey: <ph_project_api_key>, host: <ph_app_host>)"
    property_assignments = []
    topic_sections = class_data.get("topicSections", [])
    
    for section in topic_sections:
        if section.get("title") != "Instance Properties":
            continue
            
        for prop_id in section.get("identifiers", []):
            prop_ref = references.get(prop_id, {})
            if not prop_ref:
                continue
            
            fragments = prop_ref.get("fragments", [])
            has_var = any(f.get("kind") == "keyword" and f.get("text") == "var" for f in fragments)
            has_let = any(f.get("kind") == "keyword" and f.get("text") == "let" for f in fragments)
            
            if has_let and not has_var:
                continue
            if not has_var and not has_let:
                continue
            
            prop_title = prop_ref.get("title", "")
            prop_type = "Any"
            
            if prop_id.startswith("doc://"):
                prop_path = prop_id.replace("doc://PostHog/documentation/", "").replace("/", "/").lower()
                prop_file_path = os.path.join(docc_data_dir, prop_path + ".json")
                
                if os.path.exists(prop_file_path):
                    try:
                        with open(prop_file_path, 'r', encoding='utf-8') as f:
                            prop_data = json.load(f)
                        
                        for section in prop_data.get("primaryContentSections", []):
                            if section.get("kind") != "declarations":
                                continue
                            declarations = section.get("declarations", [])
                            if not declarations:
                                continue
                            
                            tokens = declarations[0].get("tokens", [])
                            found_colon = False
                            type_tokens = []
                            
                            for token in tokens:
                                text = token.get("text", "")
                                kind = token.get("kind", "")
                                
                                if ":" in text:
                                    found_colon = True
                                    continue
                                
                                if found_colon:
                                    if kind in ["typeIdentifier", "text"]:
                                        type_tokens.append(text)
                                    elif text == ",":
                                        break
                            
                            if type_tokens:
                                prop_type = "".join(type_tokens).strip()
                                break
                    except Exception:
                        pass
            
            property_assignments.append(f"config.{prop_title} = <{prop_type}>")
    
    lines = [init_line] + property_assignments + ["PostHogSDK.shared.setup(config)"]
    return "\n".join(lines)

def main():
    if len(sys.argv) != 4:
        print("Usage: python3 transform-docc.py <docc-data-directory> <output-docs.json> <version>")
        sys.exit(1)
    
    docc_data_dir = sys.argv[1]
    output_file = sys.argv[2]
    version = sys.argv[3]
    
    if not os.path.isdir(docc_data_dir):
        print(f"❌ Error: {docc_data_dir} is not a directory")
        sys.exit(1)
    
    try:
        # Process DocC directory
        result = process_docc_directory(docc_data_dir, version)
        
        # Dump the output to file
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2)
        
        print(f"✅ Successfully transformed {docc_data_dir} to {output_file}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
