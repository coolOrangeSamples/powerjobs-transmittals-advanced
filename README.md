# powerjobs-transmittals-advanced

[![Windows](https://img.shields.io/badge/Platform-Windows-lightgray.svg)](https://www.microsoft.com/en-us/windows/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue.svg)](https://microsoft.com/PowerShell/)
[![coolOrange powerEvents](https://img.shields.io/badge/coolOrange%20powerEvents-24.0.24-orange.svg)](https://doc.coolorange.com/projects/powerevents/en/stable/)
[![coolOrange powerJobs](https://img.shields.io/badge/coolOrange%20powerJobs-24.0.17-orange.svg)](https://doc.coolorange.com/projects/powerjobsprocessor/en/stable/)

## Disclaimer

THE SAMPLE CODE ON THIS REPOSITORY IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

THE USAGE OF THIS SAMPLE IS AT YOUR OWN RISK AND **THERE IS NO SUPPORT** RELATED TO IT.

---

## Description

This repository provides a sample implementation of a **Transmittals workflow** for **Autodesk Vault Professional**, utilizing **coolOrange powerJobs Client** and **powerJobs Processor**.

---

## Prerequisites

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

