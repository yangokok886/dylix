//! TweakForge C ABI. Parses bytes in process; never loads or executes the image.
use std::{ffi::CString,os::raw::c_char,panic::{catch_unwind,AssertUnwindSafe},fmt::Write};
fn signature(name:&str,types:&str)->String {if types.is_empty(){name.into()}else{reipa_objc::type_encoding::method_signature(name,types)}}
fn visit(data:&[u8], mut emit:impl FnMut(&str)->Result<(),String>)->Result<(),String>{
 let slice=reipa_macho::fat::select_arm64_slice(data).map_err(|e|format!("Invalid Mach-O: {e}"))?;
 let commands=reipa_macho::header::load_commands(&slice).map_err(|e|format!("Invalid Mach-O: {e}"))?;
 for command in commands { if command.cmd==reipa_macho::consts::LC_ENCRYPTION_INFO_64 {let encryption=reipa_macho::linkedit::parse_encryption(command.body).map_err(|e|e.to_string())?;if encryption.cryptid!=0 {return Err("ENCRYPTED: cryptid != 0; provide a decrypted binary. No headers were produced.".into());}} }
 let classes=reipa_objc::parse_objc_classes(data).map_err(|e|e.to_string())?;
 let categories=reipa_objc::parse_objc_categories(data).map_err(|e|e.to_string())?;
 if classes.len()+categories.len()>1000000{return Err("Declaration count exceeds 1000000".into());}
 let mut out=String::new();writeln!(out,"// TweakForge · REipa Objective-C metadata\n// No implementation source is recovered. Standalone protocol definitions and Swift-only declarations are not emitted.\n// {} classes, {} categories\n",classes.len(),categories.len()).unwrap();
 for c in &classes{
  out.clear();
  write!(out,"@interface {}",c.name).unwrap();if let Some(s)=&c.superclass{write!(out," : {}",s).unwrap();}if !c.protocols.is_empty(){write!(out," <{}>",c.protocols.join(", ")).unwrap();}writeln!(out).unwrap();
  if !c.ivars.is_empty(){writeln!(out,"{{").unwrap();for iv in &c.ivars{writeln!(out,"    {} {}; // +0x{:x}",reipa_objc::type_encoding::decode_type(&iv.type_enc),iv.name,iv.offset).unwrap();}writeln!(out,"}}").unwrap();}
  for m in &c.class_methods{writeln!(out,"+ {};",signature(&m.name,&m.types)).unwrap();}for m in &c.instance_methods{writeln!(out,"- {};",signature(&m.name,&m.types)).unwrap();}writeln!(out,"@end\n").unwrap();if out.len()>4*1024*1024{return Err("Single declaration exceeds 4 MB".into());}emit(&out)?;
 }
 for c in &categories{out.clear();let name=c.class_name.as_deref().unwrap_or("UnknownClass");write!(out,"@interface {} ({})",name,c.name).unwrap();if !c.protocols.is_empty(){write!(out," <{}>",c.protocols.join(", ")).unwrap();}writeln!(out).unwrap();for m in &c.class_methods{writeln!(out,"+ {};",signature(&m.name,&m.types)).unwrap();}for m in &c.instance_methods{writeln!(out,"- {};",signature(&m.name,&m.types)).unwrap();}writeln!(out,"@end\n").unwrap();if out.len()>4*1024*1024{return Err("Single declaration exceeds 4 MB".into());}emit(&out)?;}
 if classes.is_empty()&&categories.is_empty(){return Err("NO_OBJC_METADATA: no Objective-C classes or categories were recovered; Swift-only/stripped images may contain none.".into());}Ok(())
}
fn dump(data:&[u8])->Result<String,String>{let mut out=String::new();visit(data,|text|{if out.len()+text.len()>256*1024*1024{return Err("Header output exceeds 256 MB".into());}out.push_str(text);Ok(())})?;Ok(out)}
#[no_mangle]
pub unsafe extern "C" fn tf_classdump_visit_bytes(data:*const u8,len:usize,context:*mut std::ffi::c_void,emit:unsafe extern "C" fn(*const u8,usize,*mut std::ffi::c_void)->i32,error:*mut *mut c_char)->i32{
 if !error.is_null(){*error=std::ptr::null_mut();}
 let result=catch_unwind(AssertUnwindSafe(||{if data.is_null()||len<32||len>4usize*1024*1024*1024{return Err("Mach-O input must be 32 bytes to 4 GB".into());}visit(std::slice::from_raw_parts(data,len),|text|{if emit(text.as_ptr(),text.len(),context)==0{Err("Output callback stopped".into())}else{Ok(())}})}));
 match result{Ok(Ok(()))=>1,other=>{let e=match other{Ok(Err(e))=>e,_=>"Malformed metadata: parser rejected the image".into()};if !error.is_null(){*error=CString::new(e.replace('\0'," ")).unwrap().into_raw();}0}}
}
#[no_mangle]
pub unsafe extern "C" fn tf_classdump_bytes(data:*const u8,len:usize,error:*mut *mut c_char)->*mut c_char{
 if !error.is_null(){*error=std::ptr::null_mut();}
 let result=catch_unwind(AssertUnwindSafe(||{if data.is_null()||len<32||len>4usize*1024*1024*1024{return Err("Mach-O input must be 32 bytes to 4 GB".into());}dump(std::slice::from_raw_parts(data,len))}));
 let value=match result{Ok(v)=>v,Err(_)=>Err("Malformed metadata: parser rejected the image".into())};match value{Ok(s)=>CString::new(s.replace('\0'," ")).unwrap().into_raw(),Err(e)=>{if !error.is_null(){*error=CString::new(e.replace('\0'," ")).unwrap().into_raw();}std::ptr::null_mut()}}
}
#[no_mangle]
pub unsafe extern "C" fn tf_classdump_free(value:*mut c_char){if !value.is_null(){drop(CString::from_raw(value));}}
