/*********************************************************************************
* Copyright 2013 appscape gmbh
* Copyright 2014-2015 SPECURE GmbH
* 
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
* 
*   http://www.apache.org/licenses/LICENSE-2.0
* 
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*********************************************************************************/

//
//  RMBTMapOptions.swift
//  RMBT
//
//  Created by Benjamin Pucher on 30.03.15.
//  Copyright (c) 2015 Specure GmbH. All rights reserved.
//

import Foundation

// TODO: rewrite to seperate files

enum RMBTMapOptionsMapViewType: Int {
    case Standard = 0
    case Satellite = 1
    case Hybrid = 2
}

let RMBTMapOptionsOverlayAuto = RMBTMapOptionsOverlay(
    identifier: "auto",
    localizedDescription: NSLocalizedString("map.options.overlay.auto", value: "Auto", comment: "Map overlay description")
)
let RMBTMapOptionsOverlayHeatmap = RMBTMapOptionsOverlay(
    identifier: "heatmap",
    localizedDescription: NSLocalizedString("map.options.overlay.heatmap", value: "Heatmap", comment: "Map overlay description")
)
let RMBTMapOptionsOverlayPoints = RMBTMapOptionsOverlay(
    identifier: "points",
    localizedDescription: NSLocalizedString("map.options.overlay.points", value: "Points", comment: "Map overlay description")
)
let RMBTMapOptionsOverlayShapes = RMBTMapOptionsOverlay(
    identifier: "shapes",
    localizedDescription: NSLocalizedString("map.options.overlay.shapes", value: "Shapes", comment: "Map overlay description")
)
////
let RMBTMapOptionsOverlayRegions = RMBTMapOptionsOverlay(
    identifier: "regions",
    localizedDescription: NSLocalizedString("map.options.overlay.regions", value: "Regions", comment: "Map overlay description")
)
let RMBTMapOptionsOverlayMunicipality = RMBTMapOptionsOverlay(
    identifier: "municipality",
    localizedDescription: NSLocalizedString("map.options.overlay.municipality", value: "Municipality", comment: "Map overlay description")
)
let RMBTMapOptionsOverlaySettlements = RMBTMapOptionsOverlay(
    identifier: "settlements",
    localizedDescription: NSLocalizedString("map.options.overlay.settlements", value: "Settlements", comment: "Map overlay description")
)
let RMBTMapOptionsOverlayWhitespots = RMBTMapOptionsOverlay(
    identifier: "whitespots",
    localizedDescription: NSLocalizedString("map.options.overlay.whitespots", value: "White spots", comment: "Map overlay description")
)

let RMBTMapOptionsToastInfoTitle = "title"
let RMBTMapOptionsToastInfoKeys = "keys"
let RMBTMapOptionsToastInfoValues = "values"

///
class RMBTMapOptions {

    ///
    var mapViewType: RMBTMapOptionsMapViewType = .Standard

    ///
    var types = [RMBTMapOptionsType]()
    
    ///
    var overlays: [RMBTMapOptionsOverlay]

    ///
    var activeSubtype: RMBTMapOptionsSubtype
    
    ///
    var activeOverlay: RMBTMapOptionsOverlay = RMBTMapOptionsOverlayAuto

    //
    
    ///
    init(response: NSDictionary) {
        overlays = [
            RMBTMapOptionsOverlayAuto, RMBTMapOptionsOverlayHeatmap, RMBTMapOptionsOverlayPoints, /*RMBTMapOptionsOverlayShapes,*/
            RMBTMapOptionsOverlayRegions, RMBTMapOptionsOverlayMunicipality, RMBTMapOptionsOverlaySettlements, RMBTMapOptionsOverlayWhitespots
        ]
        
        // Root element, always the same
        let responseRoot = response["mapfilter"] as! NSDictionary
        
        let filters = responseRoot["mapFilters"] as! NSDictionary
        
        for typeResponse in (responseRoot["mapTypes"] as! [[String:AnyObject]]) {
            let type = RMBTMapOptionsType(response: typeResponse)
            types.append(type)
            
            // Process filters for this type
            for filterResponse in (filters[type.identifier] as! [[String:AnyObject]]) {
                let filter = RMBTMapOptionsFilter(response: filterResponse)
                type.addFilter(filter)
            }
        }
        
        // Select first subtype of first type as active per default
        activeSubtype = types[0].subtypes[0]
        
        // ..then try to actually select options from app state, if we have one
        restoreSelection()
    }

    /// Returns dictionary with following keys set, representing information to be shown in the toast
    func toastInfo() -> [String:[String]] {
        var info = [String:[String]]()
        var keys = [String]()
        var values = [String]()
        
        info[RMBTMapOptionsToastInfoTitle] = [String(format: "%@ %@", activeSubtype.type.title, activeSubtype.title)]
        
        keys.append("Overlay")
        values.append(activeOverlay.localizedDescription)
        
        for f in activeSubtype.type.filters {
            keys.append(f.title.capitalizedString)
            values.append(f.activeValue.title)
        }
        
        info[RMBTMapOptionsToastInfoKeys] = keys
        info[RMBTMapOptionsToastInfoValues] = values
        
        return info
    }

    ///
    func saveSelection() {
        let selection = RMBTMapOptionsSelection()

        selection.subtypeIdentifier = activeSubtype.identifier
        selection.overlayIdentifier = activeOverlay.identifier
        
        var activeFilters = [String:String]()
        for f in activeSubtype.type.filters {
            activeFilters[f.title] = f.activeValue.title
        }
        
        selection.activeFilters = activeFilters;
        
        RMBTSettings.sharedSettings().mapOptionsSelection = selection
    }
    
    ///
    private func restoreSelection() {
        let selection: RMBTMapOptionsSelection = RMBTSettings.sharedSettings().mapOptionsSelection
        
        if let subtypeIdentifier = selection.subtypeIdentifier {
            for t in types {
                
                let st: RMBTMapOptionsSubtype? = (t.subtypes as NSArray).bk_match({ (a: AnyObject!) -> Bool in
                    return (a as! RMBTMapOptionsSubtype).identifier == subtypeIdentifier
                }) as? RMBTMapOptionsSubtype
                
                if let _st = st {
                    activeSubtype = _st
                    break
                } else if (t.identifier == subtypeIdentifier) {
                    activeSubtype = t.subtypes[0]
                }
            }
        }
        
        if let overlayIdentifier = selection.overlayIdentifier {
            for o in overlays {
                if (o.identifier == overlayIdentifier) {
                    activeOverlay = o
                    break
                }
            }
        }
        
        if let activeFilters = selection.activeFilters {
            for f in activeSubtype.type.filters {
                if let activeFilterValueTitle = activeFilters[f.title] {
                    
                    if let v: RMBTMapOptionsFilterValue = (f.possibleValues as NSArray).bk_match({ (a: AnyObject!) -> Bool in
                        return (a as! RMBTMapOptionsFilterValue).title == activeFilterValueTitle
                    }) as? RMBTMapOptionsFilterValue {
                        f.activeValue = v
                    }
                }
            }
        }
    }
}

// Used to persist selected map options between map views
class RMBTMapOptionsSelection : NSObject {

    ///
    var subtypeIdentifier: String!
    
    ///
    var overlayIdentifier: String!
    
    ///
    var activeFilters: [String:String]!
}

///
class RMBTMapOptionsOverlay : NSObject {
    
    ///
    var identifier: String
    
    ///
    var localizedDescription: String
    
    ///
    init(identifier: String, localizedDescription: String) {
        self.identifier = identifier
        self.localizedDescription = localizedDescription
    }
}

///
class RMBTMapOptionsFilterValue : NSObject {
    
    ///
    var title: String
    
    ///
    var summary: String
    
    ///
    var isDefault: Bool = false
    
    ///
    var info: NSDictionary
    
    //
    
    ///
    init(response: [String:AnyObject]) {
        self.title = response["title"] as! String
        self.summary = response["summary"] as! String
        
        if let _default = response["default"] as? NSNumber {
            self.isDefault = _default.boolValue
        }

        var d = response
        d.removeValueForKey("title")
        d.removeValueForKey("summary")
        d.removeValueForKey("default")
        
        // Remove empty keys // TODO: check performance!
        for key in d.keys {
            if let val = (d[key] as? String) {
                if (val == "") {
                    logger.debug("removing obj for key: \(key), val: \(val)")
                    d.removeValueForKey(key)
                }
            }
        }
        
        info = d
    }
}

///
class RMBTMapOptionsFilter : NSObject {
    
    ///
    var title: String
    
    ///
    var possibleValues = [RMBTMapOptionsFilterValue]()
    
    ///
    var activeValue: RMBTMapOptionsFilterValue!
    
    //
    
    ///
    init(response: [String:AnyObject]) {
        title = response["title"] as! String

        for subresponse in (response["options"] as! [[String:AnyObject]]) {
            let filterValue = RMBTMapOptionsFilterValue(response: subresponse)
            
            if (filterValue.isDefault) {
                activeValue = filterValue
            }
            
            possibleValues.append(filterValue)
        }
    }
}


/// Type = mobile|cell|browser
class RMBTMapOptionsType : NSObject {
    
    /// localized
    var title: String
    
    /// mobile|cell|browser
    var identifier: String!
    
    ///
    var filters = [RMBTMapOptionsFilter]()
    
    ///
    var subtypes = [RMBTMapOptionsSubtype]()
    
    ///
    private var _paramsDictionary: NSMutableDictionary!
    
    //
    
    ///
    init(response: [String:AnyObject]) {
        title = response["title"] as! String
        
        super.init()
        
        for subresponse in (response["options"] as! [[String:AnyObject]]) {
            let subtype = RMBTMapOptionsSubtype(response: subresponse)
            subtype.type = self
            
            subtypes.append(subtype)
            
            var pathComponents = subtype.mapOptions.componentsSeparatedByString("/")
            
            // browser/signal -> browser
            if (identifier == nil) {
                identifier = pathComponents[0]
            } else {
                assert(identifier == pathComponents[0], "Subtype identifier invalid")
            }
        }
    }
    
    ///
    func addFilter(filter: RMBTMapOptionsFilter) {
        filters.append(filter)
    }
    
    ///
    func paramsDictionary() -> [NSObject:AnyObject] {
        if (_paramsDictionary == nil) {
            _paramsDictionary = NSMutableDictionary()
            
            for f in filters {
                _paramsDictionary.addEntriesFromDictionary(f.activeValue.info as [NSObject : AnyObject])
            }
        }
        
        return _paramsDictionary as [NSObject:AnyObject]
    }
}

/// Subtype = type + up|down|signal etc. (depending on type)
class RMBTMapOptionsSubtype : NSObject {
    
    ///
    var type: RMBTMapOptionsType!
    
    ///
    var identifier: String
    
    ///
    var title: String
    
    ///
    var summary: String
    
    ///
    var mapOptions: String
    
    ///
    var overlayType: String
    
    //
    
    ///
    init(response: [String:AnyObject]) {
        self.title = response["title"] as! String
        self.summary = response["summary"] as! String
        self.mapOptions = response["map_options"] as! String
        self.overlayType = response["overlay_type"] as! String
        
        self.identifier = mapOptions
    }

    ///
    func paramsDictionary() -> NSDictionary {
        var result = NSMutableDictionary(dictionary: [
            "map_options": mapOptions
        ])
        
        for f in type.filters {
            result.addEntriesFromDictionary(f.activeValue.info as [NSObject : AnyObject])
        }
        
        return result
    }
    
    ///
    func markerParamsDictionary() -> NSDictionary {
        var result = NSMutableDictionary(dictionary: [
            "options": [
                "map_options": mapOptions,
                "overlay_type": overlayType
            ]
        ])
        
        var filterResult = NSMutableDictionary()

        for f in type.filters {
            filterResult.addEntriesFromDictionary(f.activeValue.info as [NSObject : AnyObject])
        }
        
        result.setObject(filterResult, forKey: "filter")
        
        return result;
    }
}
