# powerjobs-transmittals-advanced

[![Windows](https://img.shields.io/badge/Platform-Windows-lightgray.svg)](https://www.microsoft.com/en-us/windows/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue.svg)](https://microsoft.com/PowerShell/)
[![coolOrange powerEvents](https://img.shields.io/badge/coolOrange%20powerEvents-24.0.24-orange.svg)](https://doc.coolorange.com/projects/powerevents/en/stable/)
[![coolOrange powerJobs](https://img.shields.io/badge/coolOrange%20powerJobs-24.0.17-orange.svg)](https://doc.coolorange.com/projects/powerjobsprocessor/en/stable/)

![image](https://github.com/user-attachments/assets/c9195678-273f-482b-b9d5-80f647ac9314)

## Disclaimer

THE SAMPLE CODE ON THIS REPOSITORY IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

THE USAGE OF THIS SAMPLE IS AT YOUR OWN RISK AND **THERE IS NO SUPPORT** RELATED TO IT.

---

## Description

This repository provides a sample implementation of a **Transmittals workflow** for **Autodesk Vault Professional**, utilizing **coolOrange powerJobs Client** and **powerJobs Processor**.

---

## Prerequisites

> **Note**: powerJobs Processor version **24.0.17** or greater and powerEvents verion **24.0.24** or greater are required for this workflow to run.

This workflow requires:

- **powerJobs Processor** installed on the Autodesk Vault **Job Processor machine**
- **powerJobs Client** installed on each Autodesk Vault **Client machine**

The repository includes files for **both** components - Client and Processor. It is assumed the workflow is deployed in a **sandbox environment** where both Vault Explorer and the Vault Job Processor are running on the **same machine**.

If you need to distribute the workflow across multiple machines:

- Use files from the `powerJobs` directory on the **Job Processor**
- Use files from the `Client Customizations` directory on each **Vault Client machine**

Further details are provided in the installation section below.

---

## Installation

> **Note**: This sample assumes that **Vault Explorer** and the **Vault Job Processor** run on the same machine.

1. **Close** Autodesk Vault Explorer and the Vault Job Processor, including **powerJobs Processor**
2. **Download or clone** this repository, and copy all files to:  
   `C:\ProgramData\coolOrange`
3. **Unblock all downloaded files** (Windows may block them):  
   [How to unblock files](https://support.coolorange.com/kb/how-to-unblock-files)
4. **Run the setup script**:  
"C:\ProgramData\coolOrange\Client Customizations\Modules\Transmittals\Setup.ps1"
This script will:
    - Prompt for Vault credentials during execution
    - Create required **Custom Objects**, **Categories**, **Lifecycles**, **States**, and **User Defined Properties** in Vault

5. **Restart** Vault Explorer to begin using the Transmittals workflow

## Feature-Level Workflow Overview

This sample solution enables **Transmittal Management** within Autodesk Vault Professional using **coolOrange powerJobs**. It provides a seamless process for preparing, validating, and distributing transmittal packages with traceability and automation.

---

### Vault Client Functionality

Vault users interact with transmittals directly in the Vault Client through a custom extension:

- **Transmittal Creation**:  
  Users can create a *Transmittal* - a special object that represents a set of files to be sent externally.

- **File Inclusion**:  
  The UI allows attaching files to the transmittal, with options to include:
  - Child references
  - Parent relationships
  - Related drawing files

- **File Output Selection**:  
  For each file, users can choose which formats should be included in the package:
  - Native format
  - PDF
  - DXF

- **Pre-Publish Validation**:  
  Before a transmittal can be published:
  - It must include at least one file
  - All files must be at their latest version (or the user is prompted with a warning)

This ensures transmittals are consistent, complete, and up-to-date before processing.

---

### Job Processor Functionality

Once a transmittal is published, the **powerJobs Processor** takes over to generate the actual package:

- **Metadata Gathering**:  
  It reads the transmittal's metadata and fetches all associated files.

- **Cover Sheet Generation**:  
  A **PDF summary** is created using an RDLC report template, detailing all files and metadata in the transmittal.

- **ZIP Package Creation**:  
  The job bundles:
  - The selected file outputs (native, PDF, DXF)
  - The generated cover sheet  
  ...into a single ZIP archive.

- **Vault Archival**:  
  The final ZIP and its PDF cover are uploaded to a specified folder within Vault (default: `$/Transmittals`), ensuring traceability and centralized storage.

---

### End-to-End Workflow

1. **User creates and configures a transmittal** in Vault.
2. **Transmittal is validated and published** through Vault lifecycle state change.
3. **powerJobs Processor picks up the job**, generates all outputs, and stores the final package in Vault.
4. The transmittal is now complete, stored, and ready to be sent externally.
